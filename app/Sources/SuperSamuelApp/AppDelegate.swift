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
    private var audioStopTask: Task<Void, Never>?
    private var lastTranscript = ""
    private var targetApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlayController = OverlayWindowController(state: appState)
        overlayController?.onStop = { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleRecording()
            }
        }
        overlayController?.onCopyAndStop = { [weak self] in
            Task { @MainActor [weak self] in
                self?.copyCurrentAndStop()
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
        audioStopTask?.cancel()
        audioStopTask = nil
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

    private func copyCurrentAndStop() {
        // Copy current transcript to clipboard
        let trimmed = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            clipboard.setString(trimmed)
        }
        // Then stop recording
        toggleRecording()
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
            lastTranscript = ""
            appState.setTranscriptPreview(fullText: "")

            let session = STTSessionService()
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

        guard let sttSession else {
            isTransitioning = false
            return
        }

        // Capture target app before any async work
        let targetApp = self.targetApplication
        let shouldAutoPaste = settings.autoPaste
        let shouldRestoreClipboard = settings.restoreClipboard
        let transcript = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipboardSnapshot = (!transcript.isEmpty && shouldAutoPaste && shouldRestoreClipboard) ? clipboard.snapshot() : nil

        appState.setPhase(.finalizing)
        menuBarController?.updateStatusTitle(for: .finalizing)
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        self.lastTranscript = transcript
        self.appState.setTranscriptPreview(fullText: transcript)
        self.overlayController?.hide()
        self.sttSession = nil
        self.targetApplication = nil
        isTransitioning = false

        if !transcript.isEmpty {
            clipboard.setString(transcript)
        }

        self.appState.setPhase(.idle)
        self.appState.setElapsed(seconds: 0)
        self.menuBarController?.updateStatusTitle(for: .idle)

        if !transcript.isEmpty && shouldAutoPaste {
            let targetApp = targetApp
            let clipboardSnapshot = clipboardSnapshot
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                guard self.permissions.hasAccessibilityPermission(prompt: false) else {
                    return
                }

                self.textInsertion.pasteClipboardContents(into: targetApp)

                if let clipboardSnapshot {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                        self?.clipboard.restore(clipboardSnapshot)
                    }
                }
            }
        }

        audioStopTask?.cancel()
        audioStopTask = Task.detached(priority: .userInitiated) { [audioCapture] in
            audioCapture.stop()
        }

        sttSession.cancel()
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
        audioStopTask?.cancel()
        audioStopTask = nil
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
