import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let state: AppState
    private var panel: NSPanel?

    init(state: AppState) {
        self.state = state
    }

    func show() {
        let panel = ensurePanel()
        center(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false

        let contentView = RecordingOverlayView(state: state)
        let host = NSHostingView(rootView: contentView)
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        self.panel = panel
        return panel
    }

    private func center(_ panel: NSPanel) {
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            panel.center()
            return
        }

        let originX = screenFrame.midX - (panel.frame.width / 2)
        let originY = screenFrame.midY - (panel.frame.height / 2)
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
