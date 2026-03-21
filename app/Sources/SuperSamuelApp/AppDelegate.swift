import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let settings = SettingsStore()
    private let permissions = PermissionsService()
    private let hotkeyService = HotkeyService()
    private let audioCapture = AudioCaptureService()
    private let clipboard = ClipboardService()
    private let openRouterService = OpenRouterService()
    private let screenshotCapture = ScreenshotCaptureService()
    private lazy var textInsertion = TextInsertionService(clipboard: clipboard)

    private var overlayController: OverlayWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var menuBarController: MenuBarController?
    private var sttSession: STTSessionService?

    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var isTransitioning = false
    private var lastTranscript = ""
    private var targetApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureApplicationMenu()

        overlayController = OverlayWindowController(state: appState)
        overlayController?.onStop = { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleRecording()
            }
        }
        overlayController?.onCopy = { [weak self] in
            Task { @MainActor [weak self] in
                self?.copyCurrentTranscript()
            }
        }
        overlayController?.onAttachScreenshot = { [weak self] in
            Task { @MainActor [weak self] in
                self?.captureScreenshotFlow()
            }
        }
        overlayController?.onClearScreenshot = { [weak self] in
            Task { @MainActor [weak self] in
                self?.clearAttachedScreenshot()
            }
        }
        menuBarController = MenuBarController(settings: settings)
        menuBarController?.onToggleRecording = { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleRecording()
            }
        }
        menuBarController?.onCopyLastTranscript = { [weak self] in
            Task { @MainActor [weak self] in
                self?.copyLastTranscript()
            }
        }
        menuBarController?.onOpenSettings = { [weak self] in
            Task { @MainActor [weak self] in
                self?.openSettingsFlow()
            }
        }
        menuBarController?.onOpenAccessibilitySettings = { [weak self] in
            Task { @MainActor [weak self] in
                self?.openAccessibilitySettingsFlow()
            }
        }

        if !hotkeyService.start(onTrigger: { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleRecording()
            }
        }) {
            print("Failed to register global hotkey")
        }

        audioCapture.onChunk = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.sttSession?.sendAudioChunk(data)
            }
        }

        audioCapture.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.appState.pushLevel(level)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        audioCapture.stop()
        sttSession?.cancel()
        hotkeyService.stop()
        clearAttachedScreenshot()
    }

    private func toggleRecording() {
        switch appState.phase {
        case .idle, .done, .error(_):
            Task { await startRecordingFlow() }
        case .recording:
            Task { await stopRecordingFlow() }
        case .finalizing, .inserting:
            forceResetToIdle()
        }
    }

    private func copyLastTranscript() {
        copyTranscript(lastTranscript)
    }

    private func copyCurrentTranscript() {
        copyTranscript(lastTranscript)
    }

    private func startRecordingFlow() async {
        guard !isTransitioning else {
            return
        }
        isTransitioning = true
        defer { isTransitioning = false }

        do {
            targetApplication = NSWorkspace.shared.frontmostApplication
            try await permissions.ensureMicrophonePermission()
            clearAttachedScreenshot()
            lastTranscript = ""
            appState.aiCleanupEnabled = settings.aiCleanupEnabledByDefault
            appState.setTranscriptPreview(fullText: "")

            let session = STTSessionService(settings: settings)
            session.onSnapshot = { [weak self, weak session] snapshot in
                guard
                    let self,
                    let session,
                    let currentSession = self.sttSession,
                    currentSession === session
                else {
                    return
                }
                self.lastTranscript = snapshot.combinedText
                self.appState.setTranscriptPreview(fullText: snapshot.combinedText)
            }

            try await session.start()
            sttSession = session

            try audioCapture.start()
            startedAt = Date()
            startElapsedTimer()

            appState.resetForRecording()
            overlayController?.show()
            menuBarController?.updateStatusTitle(for: .recording)
        } catch {
            handleError(error.localizedDescription)
        }
    }

    private func stopRecordingFlow() async {
        guard !isTransitioning else {
            return
        }
        isTransitioning = true

        guard let sttSession else {
            isTransitioning = false
            return
        }

        // Capture target app before any async work
        let targetApp = self.targetApplication
        let shouldAutoPaste = settings.autoPaste
        let shouldRestoreClipboard = settings.restoreClipboard
        let shouldRunAICleanup = appState.aiCleanupEnabled
        let attachedScreenshotURL = appState.attachedScreenshot?.fileURL
        let clipboardSnapshot = shouldAutoPaste && shouldRestoreClipboard ? clipboard.snapshot() : nil

        appState.setPhase(.finalizing)
        menuBarController?.updateStatusTitle(for: .finalizing)
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        startedAt = nil
        let finalChunk = audioCapture.stop()
        if !finalChunk.isEmpty {
            sttSession.sendAudioChunk(finalChunk)
        }
        isTransitioning = false

        do {
            let finalizedTranscript = try await sttSession.finishAndWait()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let currentSession = self.sttSession, currentSession === sttSession else {
                return
            }

            var transcriptToDeliver = finalizedTranscript

            if shouldRunAICleanup && !finalizedTranscript.isEmpty && settings.hasOpenRouterCleanupConfiguration {
                self.appState.setPhase(.inserting)
                self.menuBarController?.updateStatusTitle(for: .inserting)
                self.appState.setTranscriptPreview(fullText: finalizedTranscript)

                do {
                    let cleanedTranscript = try await cleanupTranscript(
                        finalizedTranscript,
                        screenshotURL: attachedScreenshotURL
                    ).trimmingCharacters(in: .whitespacesAndNewlines)

                    guard let currentSession = self.sttSession, currentSession === sttSession else {
                        return
                    }

                    if !cleanedTranscript.isEmpty {
                        transcriptToDeliver = cleanedTranscript
                    }
                } catch {
                    print("OpenRouter cleanup skipped: \(error.localizedDescription)")

                    guard let currentSession = self.sttSession, currentSession === sttSession else {
                        return
                    }
                }
            }

            self.lastTranscript = transcriptToDeliver
            self.appState.setTranscriptPreview(fullText: transcriptToDeliver)
            self.overlayController?.hide()
            self.clearAttachedScreenshot()

            if !transcriptToDeliver.isEmpty {
                clipboard.setString(transcriptToDeliver)
            }

            if !transcriptToDeliver.isEmpty && shouldAutoPaste && permissions.hasAccessibilityPermission(prompt: false) {
                textInsertion.pasteClipboardContents(into: targetApp)

                if let clipboardSnapshot {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                        self?.clipboard.restore(clipboardSnapshot)
                    }
                }
            }

            sttSession.cancel()
            self.sttSession = nil
            self.targetApplication = nil
            self.appState.setPhase(.idle)
            self.appState.setElapsed(seconds: 0)
            self.menuBarController?.updateStatusTitle(for: .idle)
        } catch is CancellationError {
            guard let currentSession = self.sttSession, currentSession === sttSession else {
                return
            }

            sttSession.cancel()
            self.sttSession = nil
            self.targetApplication = nil
            self.overlayController?.hide()
            self.clearAttachedScreenshot()
            self.appState.setPhase(.idle)
            self.appState.setElapsed(seconds: 0)
            self.menuBarController?.updateStatusTitle(for: .idle)
        } catch {
            guard let currentSession = self.sttSession, currentSession === sttSession else {
                return
            }

            sttSession.cancel()
            self.sttSession = nil
            self.targetApplication = nil
            self.overlayController?.hide()
            self.clearAttachedScreenshot()
            handleError(error.localizedDescription)
        }
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startedAt = self.startedAt else {
                    return
                }
                self.appState.setElapsed(seconds: Date().timeIntervalSince(startedAt))
            }
        }
    }

    private func forceResetToIdle() {
        isTransitioning = false  // Critical: reset this flag so new recordings can start
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        startedAt = nil
        audioCapture.stop()
        sttSession?.cancel()
        sttSession = nil
        targetApplication = nil
        clearAttachedScreenshot()
        overlayController?.hide()
        appState.setPhase(.idle)
        appState.setElapsed(seconds: 0)
        menuBarController?.updateStatusTitle(for: .idle)
    }

    private func copyTranscript(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        clipboard.setString(trimmed)
    }

    private func openAccessibilitySettingsFlow() {
        _ = permissions.hasAccessibilityPermission(prompt: true)
        permissions.openAccessibilitySettings()
    }

    private func openSettingsFlow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings)
        }

        settingsWindowController?.show()
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About SuperSamuel",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide SuperSamuel",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        ).keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit SuperSamuel",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func captureScreenshotFlow() {
        guard appState.phase == .recording, !appState.isCapturingScreenshot else {
            return
        }

        appState.isCapturingScreenshot = true
        appState.screenshotStatusMessage = nil

        defer {
            appState.isCapturingScreenshot = false
        }

        do {
            try permissions.ensureScreenRecordingPermission(prompt: true)
        } catch {
            appState.screenshotStatusMessage = "\(error.localizedDescription) Enable it in System Settings, then retake."
            return
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let candidates = [NSWorkspace.shared.frontmostApplication, targetApplication]
            .compactMap { $0 }
            .filter { $0.processIdentifier != currentProcessIdentifier }
            .reduce(into: [NSRunningApplication]()) { partialResult, application in
                if !partialResult.contains(where: { $0.processIdentifier == application.processIdentifier }) {
                    partialResult.append(application)
                }
            }

        var lastError: Error?

        for application in candidates {
            do {
                let attachment = try screenshotCapture.captureWindow(for: application)
                let previousAttachment = appState.attachedScreenshot
                appState.attachedScreenshot = attachment
                appState.screenshotStatusMessage = nil
                screenshotCapture.remove(previousAttachment)
                return
            } catch {
                lastError = error
            }
        }

        appState.screenshotStatusMessage = lastError?.localizedDescription ?? "Couldn't attach a screenshot."
    }

    private func clearAttachedScreenshot() {
        screenshotCapture.remove(appState.attachedScreenshot)
        appState.attachedScreenshot = nil
        appState.screenshotStatusMessage = nil
        appState.isCapturingScreenshot = false
    }

    private func cleanupTranscript(_ transcript: String, screenshotURL: URL?) async throws -> String {
        do {
            return try await openRouterService.cleanupTranscript(
                apiKey: settings.openRouterAPIKey,
                model: settings.openRouterModel,
                rewriteInstruction: settings.openRouterCleanupPrompt,
                rawTranscript: transcript,
                screenshotURL: screenshotURL
            )
        } catch {
            guard screenshotURL != nil else {
                throw error
            }

            print("OpenRouter cleanup with screenshot failed, retrying without image: \(error.localizedDescription)")
            return try await openRouterService.cleanupTranscript(
                apiKey: settings.openRouterAPIKey,
                model: settings.openRouterModel,
                rewriteInstruction: settings.openRouterCleanupPrompt,
                rawTranscript: transcript,
                screenshotURL: nil
            )
        }
    }

    private func handleError(_ message: String) {
        appState.setPhase(.error(message))
        menuBarController?.updateStatusTitle(for: .error(message))
        overlayController?.show()
        targetApplication = nil
        clearAttachedScreenshot()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.overlayController?.hide()
                self.appState.setPhase(.idle)
                self.menuBarController?.updateStatusTitle(for: .idle)
            }
        }
    }
}
