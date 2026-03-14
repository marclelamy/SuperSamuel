import AVFoundation
import AppKit
import ApplicationServices
import Foundation
import IOKit.hid

enum AccessibilityPermissionState {
    case granted
    case denied
    case notDetermined
}

enum PermissionError: LocalizedError {
    case microphoneDenied
    case accessibilityDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone permission is required."
        case .accessibilityDenied:
            return "Accessibility permission is required for automatic paste."
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

    func accessibilityPermissionState() -> AccessibilityPermissionState {
        if CGPreflightPostEventAccess() || AXIsProcessTrusted() {
            return .granted
        }

        switch IOHIDCheckAccess(kIOHIDRequestTypePostEvent) {
        case kIOHIDAccessTypeGranted:
            return .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .notDetermined
        }
    }

    func hasAccessibilityPermission(prompt: Bool) -> Bool {
        if CGPreflightPostEventAccess() || AXIsProcessTrusted() {
            return true
        }

        guard prompt else {
            return false
        }

        if CGRequestPostEventAccess() {
            return true
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func openAccessibilitySettings() {
        openPrivacySettings([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ])
    }

    private func openPrivacySettings(_ urlStrings: [String]) {
        for rawURL in urlStrings {
            guard let url = URL(string: rawURL) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
