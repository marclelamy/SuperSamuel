import AVFoundation
import AppKit
import ApplicationServices
import Foundation

enum PermissionError: LocalizedError {
    case microphoneDenied
    case accessibilityDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone permission is required."
        case .accessibilityDenied:
            return "Accessibility permission is required for global shortcuts and paste."
        }
    }
}

@MainActor
final class PermissionsService {
    func ensureMicrophonePermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                throw PermissionError.microphoneDenied
            }
        case .denied, .restricted:
            throw PermissionError.microphoneDenied
        @unknown default:
            throw PermissionError.microphoneDenied
        }
    }

    func ensureAccessibilityPermission(prompt: Bool) throws {
        let trusted = hasAccessibilityPermission(prompt: prompt)
        if !trusted {
            throw PermissionError.accessibilityDenied
        }
    }

    func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
