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
            let duplicate = NSPasteboardItem()
            var copiedAnyType = false

            for type in item.types {
                if let data = item.data(forType: type) {
                    duplicate.setData(data, forType: type)
                    copiedAnyType = true
                } else if let string = item.string(forType: type) {
                    duplicate.setString(string, forType: type)
                    copiedAnyType = true
                }
            }

            return copiedAnyType ? duplicate : nil
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
