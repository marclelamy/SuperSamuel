import AppKit
import Foundation

@MainActor
final class MenuBarController: NSObject {
    var onToggleRecording: (() -> Void)?
    var onCopyLastTranscript: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenAccessibilitySettings: (() -> Void)?
    var onSettingsChanged: (() -> Void)?

    private let statusItem: NSStatusItem
    private let settings: SettingsStore

    private let toggleRecordingItem = NSMenuItem(title: "Start Recording (Option+Space)", action: nil, keyEquivalent: "")
    private let copyItem = NSMenuItem(title: "Copy Last Transcript", action: nil, keyEquivalent: "")
    private let autoPasteItem = NSMenuItem(title: "Auto Paste Result", action: nil, keyEquivalent: "")
    private let restoreClipboardItem = NSMenuItem(title: "Restore Clipboard", action: nil, keyEquivalent: "")
    private let openSettingsItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: ",")
    private let openAccessibilityItem = NSMenuItem(title: "Open Accessibility Settings", action: nil, keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit SuperSamuel", action: nil, keyEquivalent: "q")

    init(settings: SettingsStore) {
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureMenu()
        updateStatusTitle(for: .idle)
    }

    func updateStatusTitle(for phase: DictationPhase) {
        guard let button = statusItem.button else {
            return
        }

        switch phase {
        case .idle:
            button.title = "SS"
            toggleRecordingItem.title = "Start Recording (Option+Space)"
        case .recording:
            button.title = "SS REC"
            toggleRecordingItem.title = "Stop Recording (Option+Space)"
        case .finalizing:
            button.title = "SS ..."
            toggleRecordingItem.title = "Cancel Finalizing (Option+Space)"
        case .inserting:
            button.title = "SS AI"
            toggleRecordingItem.title = "Cancel AI Cleanup (Option+Space)"
        case .done:
            button.title = "SS"
            toggleRecordingItem.title = "Start Recording (Option+Space)"
        case .error(_):
            button.title = "SS ERR"
            toggleRecordingItem.title = "Start Recording (Option+Space)"
        }
    }

    private func configureMenu() {
        let menu = NSMenu()

        toggleRecordingItem.target = self
        toggleRecordingItem.action = #selector(handleToggleRecording)

        copyItem.target = self
        copyItem.action = #selector(handleCopyLastTranscript)

        autoPasteItem.target = self
        autoPasteItem.action = #selector(handleToggleAutoPaste)

        restoreClipboardItem.target = self
        restoreClipboardItem.action = #selector(handleToggleRestoreClipboard)

        openSettingsItem.target = self
        openSettingsItem.action = #selector(handleOpenSettings)

        openAccessibilityItem.target = self
        openAccessibilityItem.action = #selector(handleOpenAccessibility)

        quitItem.target = self
        quitItem.action = #selector(handleQuit)

        menu.addItem(toggleRecordingItem)
        menu.addItem(copyItem)
        menu.addItem(.separator())
        menu.addItem(autoPasteItem)
        menu.addItem(restoreClipboardItem)
        menu.addItem(.separator())
        menu.addItem(openSettingsItem)
        menu.addItem(openAccessibilityItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshCheckmarks()
    }

    private func refreshCheckmarks() {
        autoPasteItem.state = settings.autoPaste ? .on : .off
        restoreClipboardItem.state = settings.restoreClipboard ? .on : .off
        restoreClipboardItem.isEnabled = settings.autoPaste
    }

    @objc
    private func handleToggleRecording() {
        onToggleRecording?()
    }

    @objc
    private func handleCopyLastTranscript() {
        onCopyLastTranscript?()
    }

    @objc
    private func handleToggleAutoPaste() {
        settings.autoPaste.toggle()
        refreshCheckmarks()
        onSettingsChanged?()
    }

    @objc
    private func handleToggleRestoreClipboard() {
        settings.restoreClipboard.toggle()
        refreshCheckmarks()
        onSettingsChanged?()
    }

    @objc
    private func handleOpenSettings() {
        onOpenSettings?()
    }

    @objc
    private func handleOpenAccessibility() {
        onOpenAccessibilitySettings?()
    }

    @objc
    private func handleQuit() {
        NSApp.terminate(nil)
    }
}
