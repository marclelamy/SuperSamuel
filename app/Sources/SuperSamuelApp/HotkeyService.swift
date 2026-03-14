import AppKit
import Carbon
import Foundation

final class HotkeyService {
    private static let hotKeySignature: OSType = {
        var result: FourCharCode = 0
        for scalar in "SSHK".utf16 {
            result = (result << 8) + FourCharCode(scalar)
        }
        return result
    }()

    private static var activeService: HotkeyService?
    private static var eventHandler: EventHandlerRef?

    private var hotKeyRef: EventHotKeyRef?
    private var onTrigger: (() -> Void)?
    private var lastTriggerTime: TimeInterval = 0

    deinit {
        stop()
    }

    @discardableResult
    func start(onTrigger: @escaping () -> Void) -> Bool {
        stop()
        self.onTrigger = onTrigger
        Self.activeService = self

        guard Self.installEventHandlerIfNeeded() else {
            self.onTrigger = nil
            Self.activeService = nil
            return false
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            self.onTrigger = nil
            Self.activeService = nil
            return false
        }

        self.hotKeyRef = hotKeyRef
        return true
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if Self.activeService === self {
            Self.activeService = nil
        }

        onTrigger = nil
    }

    private static func installEventHandlerIfNeeded() -> Bool {
        guard eventHandler == nil else {
            return true
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, _ in
                guard let service = HotkeyService.activeService else {
                    return OSStatus(eventNotHandledErr)
                }
                return service.handleHotKeyEvent(event)
            },
            1,
            &eventSpec,
            nil,
            &eventHandler
        )

        return status == noErr
    }

    private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return status
        }
        guard hotKeyID.signature == Self.hotKeySignature else {
            return OSStatus(eventNotHandledErr)
        }

        fireTriggerIfNeeded()
        return noErr
    }

    private func fireTriggerIfNeeded() {
        let now = Date().timeIntervalSince1970
        if now - lastTriggerTime < 0.15 {
            return
        }
        lastTriggerTime = now

        DispatchQueue.main.async { [weak self] in
            self?.onTrigger?()
        }
    }
}
