import AppKit
import Foundation

enum TextInsertionResult {
    case pastedFromClipboard
    case copiedOnly
}

@MainActor
final class TextInsertionService {
    private let clipboard: ClipboardService

    init(clipboard: ClipboardService) {
        self.clipboard = clipboard
    }

    func deliver(
        text: String,
        targetApplication: NSRunningApplication?,
        autoPaste: Bool,
        restoreClipboard: Bool
    ) -> TextInsertionResult {
        if !autoPaste {
            clipboard.setString(text)
            return .copiedOnly
        }

        let snapshot = restoreClipboard ? clipboard.snapshot() : nil
        clipboard.setString(text)
        targetApplication?.activate(options: [.activateIgnoringOtherApps])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.simulateCommandV()

            if let snapshot {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    self?.clipboard.restore(snapshot)
                }
            }
        }

        return .pastedFromClipboard
    }

    private func simulateCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        let keyCodeForV: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCodeForV, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
