import AVFoundation
import AppKit
import ApplicationServices
import Foundation

enum PermissionError: LocalizedError {
    case microphoneDenied
    case screenRecordingDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone permission is required."
        case .screenRecordingDenied:
            return "Screen Recording permission is required to attach a screenshot."
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

    func ensureScreenRecordingPermission(prompt: Bool) throws {
        let granted = hasScreenRecordingPermission(prompt: prompt)
        if !granted {
            throw PermissionError.screenRecordingDenied
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

    func hasScreenRecordingPermission(prompt: Bool) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        guard prompt else {
            return false
        }

        return CGRequestScreenCaptureAccess()
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
