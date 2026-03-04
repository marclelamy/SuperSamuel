import AppKit
import Foundation

struct ClipboardSnapshot {
    let items: [NSPasteboardItem]
}

@MainActor
final class ClipboardService {
    private let pasteboard = NSPasteboard.general

    func snapshot() -> ClipboardSnapshot {
        let copiedItems = (pasteboard.pasteboardItems ?? []).compactMap { item in
            item.copy() as? NSPasteboardItem
        }
        return ClipboardSnapshot(items: copiedItems)
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        pasteboard.clearContents()
        if !snapshot.items.isEmpty {
            pasteboard.writeObjects(snapshot.items)
        }
    }

    func setString(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
