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
    private lazy var textInsertion = TextInsertionService(clipboard: clipboard)

    private var overlayController: OverlayWindowController?
    private var menuBarController: MenuBarController?
    private var sttSession: STTSessionService?

    private var elapsedTimer: Timer?
    private var startedAt: Date?
    private var isTransitioning = false
    private var lastTranscript = ""
    private var targetApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlayController = OverlayWindowController(state: appState)
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
        menuBarController?.onOpenAccessibilitySettings = { [weak self] in
            Task { @MainActor [weak self] in
                self?.openAccessibilitySettingsFlow()
            }
        }

        hotkeyService.start { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleRecording()
            }
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

        primeAccessibilityPrompt()
    }

    func applicationWillTerminate(_ notification: Notification) {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        audioCapture.stop()
        sttSession?.cancel()
        hotkeyService.stop()
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
        let trimmed = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        clipboard.setString(trimmed)
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

            // Dictation can still work without Accessibility; prompt, but don't block.
            _ = permissions.hasAccessibilityPermission(prompt: true)

            let session = STTSessionService(brokerURL: settings.brokerURL)
            session.onSnapshot = { [weak self] snapshot in
                guard let self else {
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
        defer { isTransitioning = false }

        guard let sttSession else {
            return
        }

        appState.setPhase(.finalizing)
        menuBarController?.updateStatusTitle(for: .finalizing)
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        audioCapture.stop()

        do {
            let transcript = try await sttSession.finishAndWait(timeoutMs: settings.finalizationTailMs)
            let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lastTranscript = trimmedTranscript
            self.appState.setTranscriptPreview(fullText: trimmedTranscript)
            self.appState.setPhase(.inserting)
            self.menuBarController?.updateStatusTitle(for: .inserting)

            self.overlayController?.hide()

            let canAutoPaste = settings.autoPaste && permissions.hasAccessibilityPermission(prompt: false)
            if !trimmedTranscript.isEmpty {
                _ = textInsertion.deliver(
                    text: trimmedTranscript,
                    targetApplication: targetApplication,
                    autoPaste: canAutoPaste,
                    restoreClipboard: settings.restoreClipboard
                )
            }

            self.sttSession?.cancel()
            self.sttSession = nil
            self.targetApplication = nil

            self.appState.setPhase(.done)
            self.menuBarController?.updateStatusTitle(for: .done)
            completeSessionAndReturnToIdle()
        } catch {
            sttSession.cancel()
            self.sttSession = nil
            self.targetApplication = nil
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

    private func completeSessionAndReturnToIdle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                self.overlayController?.hide()
                self.appState.setPhase(.idle)
                self.appState.setElapsed(seconds: 0)
                self.menuBarController?.updateStatusTitle(for: .idle)
            }
        }
    }

    private func forceResetToIdle() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        audioCapture.stop()
        sttSession?.cancel()
        sttSession = nil
        targetApplication = nil
        overlayController?.hide()
        appState.setPhase(.idle)
        appState.setElapsed(seconds: 0)
        menuBarController?.updateStatusTitle(for: .idle)
    }

    private func openAccessibilitySettingsFlow() {
        _ = permissions.hasAccessibilityPermission(prompt: true)
        permissions.openAccessibilitySettings()
    }

    private func primeAccessibilityPrompt() {
        _ = permissions.hasAccessibilityPermission(prompt: true)
    }

    private func handleError(_ message: String) {
        appState.setPhase(.error(message))
        menuBarController?.updateStatusTitle(for: .error(message))
        overlayController?.show()
        targetApplication = nil

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
