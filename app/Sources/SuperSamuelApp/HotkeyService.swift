import AppKit
import Foundation

final class HotkeyService {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onTrigger: (() -> Void)?
    private var lastTriggerTime: TimeInterval = 0

    deinit {
        stop()
    }

    func start(onTrigger: @escaping () -> Void) {
        stop()
        self.onTrigger = onTrigger

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            if self.matchesShortcut(event) {
                self.fireTriggerIfNeeded()
                return nil
            }
            return event
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        onTrigger = nil
    }

    private func handle(_ event: NSEvent) {
        guard matchesShortcut(event) else {
            return
        }
        fireTriggerIfNeeded()
    }

    private func matchesShortcut(_ event: NSEvent) -> Bool {
        if event.isARepeat {
            return false
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 49 && flags == [.option]
    }

    private func fireTriggerIfNeeded() {
        let now = Date().timeIntervalSince1970
        // Global + local monitors can both fire around the same time.
        if now - lastTriggerTime < 0.15 {
            return
        }
        lastTriggerTime = now
        onTrigger?()
    }
}
