import AppKit
import CoreGraphics
import Foundation

struct AttachedScreenshot: Identifiable {
    let id = UUID()
    let fileURL: URL
    let previewImage: NSImage
    let sourceDescription: String
}

enum ScreenshotCaptureError: LocalizedError {
    case missingTargetApplication
    case noVisibleWindow(String)
    case imageCreationFailed
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .missingTargetApplication:
            return "No target app was available for the screenshot."
        case .noVisibleWindow(let appName):
            return "Couldn't find a visible window for \(appName)."
        case .imageCreationFailed:
            return "Couldn't capture the selected window."
        case .fileWriteFailed:
            return "Couldn't save the screenshot."
        }
    }
}

@MainActor
final class ScreenshotCaptureService {
    private let fileManager: FileManager
    private let tempDirectory: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.tempDirectory = fileManager.temporaryDirectory.appendingPathComponent("SuperSamuel", isDirectory: true)
    }

    func captureWindow(for application: NSRunningApplication?) throws -> AttachedScreenshot {
        guard let application else {
            throw ScreenshotCaptureError.missingTargetApplication
        }

        let appName = application.localizedName ?? "the current app"
        guard let windowInfo = frontmostWindow(for: application.processIdentifier) else {
            throw ScreenshotCaptureError.noVisibleWindow(appName)
        }

        guard
            let cgImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowInfo.windowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
        else {
            throw ScreenshotCaptureError.imageCreationFailed
        }

        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let fileURL = tempDirectory.appendingPathComponent("window-context-\(UUID().uuidString).jpg")
        try writeJPEGImage(cgImage, to: fileURL)

        let previewImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        let sourceDescription = windowInfo.sourceDescription(defaultAppName: appName)

        return AttachedScreenshot(
            fileURL: fileURL,
            previewImage: previewImage,
            sourceDescription: sourceDescription
        )
    }

    func remove(_ attachment: AttachedScreenshot?) {
        guard let attachment else {
            return
        }

        try? fileManager.removeItem(at: attachment.fileURL)
    }

    private func frontmostWindow(for processIdentifier: pid_t) -> CapturableWindowInfo? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for dictionary in rawWindowInfo {
            guard let window = CapturableWindowInfo(dictionary: dictionary) else {
                continue
            }

            if window.ownerPID == processIdentifier &&
                window.layer == 0 &&
                window.alpha > 0 &&
                window.bounds.width >= 120 &&
                window.bounds.height >= 80
            {
                return window
            }
        }

        return nil
    }

    private func writeJPEGImage(_ image: CGImage, to url: URL) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard
            let data = bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.82]
            )
        else {
            throw ScreenshotCaptureError.fileWriteFailed
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ScreenshotCaptureError.fileWriteFailed
        }
    }
}

private struct CapturableWindowInfo {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let layer: Int
    let alpha: Double
    let bounds: CGRect

    init?(dictionary: [String: Any]) {
        guard
            let windowNumber = dictionary[kCGWindowNumber as String] as? NSNumber,
            let ownerPID = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
            let ownerName = dictionary[kCGWindowOwnerName as String] as? String,
            let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
        else {
            return nil
        }

        self.windowID = CGWindowID(windowNumber.uint32Value)
        self.ownerPID = pid_t(ownerPID.int32Value)
        self.ownerName = ownerName
        self.title = (dictionary[kCGWindowName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        self.alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        self.bounds = bounds
    }

    func sourceDescription(defaultAppName: String) -> String {
        if !title.isEmpty {
            return title
        }

        if !ownerName.isEmpty {
            return ownerName
        }

        return defaultAppName
    }
}
