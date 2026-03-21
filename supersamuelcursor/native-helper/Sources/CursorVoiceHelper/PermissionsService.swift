import AVFoundation
import Foundation

enum PermissionError: LocalizedError {
    case microphoneDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone permission is required."
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
}
