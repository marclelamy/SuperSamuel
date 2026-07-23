import Foundation

struct AudioInputDeviceInfo: Codable, Equatable {
    let name: String
    let uniqueID: String
}

struct AudioSignalSummary: Codable, Equatable {
    let frameCount: Int64
    let sampleCount: Int64
    let duration: TimeInterval
    let rms: Float
    let peak: Float
    let sizeBytes: Int64

    var hasRecordedSignal: Bool {
        frameCount > 0 && peak > 0.000_01
    }
}

struct AudioCaptureHealthSnapshot: Equatable {
    let elapsed: TimeInterval
    let rawLevel: Float
    let writtenLevel: Float
    let framesWritten: Int64
    let sampleRate: Double
    let lastWriteAge: TimeInterval
    let writingElapsed: TimeInterval
    let conversionMismatchDuration: TimeInterval
    let fileSizeBytes: Int64
    let failureDescription: String?

    var writtenDuration: TimeInterval {
        guard sampleRate > 0 else {
            return 0
        }
        return Double(framesWritten) / sampleRate
    }
}

enum AudioCaptureHealthIssue: LocalizedError, Equatable {
    case writeFailed(String)
    case outputStalled
    case convertedOutputSilent
    case recordingTooShort(expected: TimeInterval, actual: TimeInterval)
    case persistedAudioSilent
    case persistedFrameMismatch(written: Int64, persisted: Int64)

    var errorDescription: String? {
        switch self {
        case .writeFailed(let message):
            return "Audio could not be written to disk: \(message) The recording was stopped and kept."
        case .outputStalled:
            return "The microphone was active, but audio stopped reaching the recording file. The recording was stopped and kept."
        case .convertedOutputSilent:
            return "The microphone had a signal, but the converted audio being written was silent. The recording was stopped and kept."
        case .recordingTooShort(let expected, let actual):
            return String(
                format: "The saved audio is incomplete (expected about %.1f seconds, found %.1f). The recording was kept.",
                expected,
                actual
            )
        case .persistedAudioSilent:
            return "The saved WAV contains only digital silence. The recording was kept instead of being sent."
        case .persistedFrameMismatch(let written, let persisted):
            return "The saved WAV failed verification (\(written) frames written, \(persisted) frames readable). The recording was kept."
        }
    }
}

enum AudioCaptureHealthPolicy {
    private static let liveGraceDuration: TimeInterval = 2
    private static let initialWriteGraceDuration: TimeInterval = 8
    private static let maximumWriteGap: TimeInterval = 1.5
    private static let maximumConversionMismatch: TimeInterval = 1
    private static let minimumProgressRatio = 0.6
    private static let minimumPersistedDurationRatio = 0.8
    static func liveIssue(
        for snapshot: AudioCaptureHealthSnapshot
    ) -> AudioCaptureHealthIssue? {
        if let failure = snapshot.failureDescription {
            return .writeFailed(failure)
        }

        if snapshot.framesWritten == 0 {
            return snapshot.elapsed >= initialWriteGraceDuration
                ? .outputStalled
                : nil
        }

        guard snapshot.elapsed >= liveGraceDuration else {
            return nil
        }

        if snapshot.lastWriteAge >= maximumWriteGap {
            return .outputStalled
        }

        if snapshot.conversionMismatchDuration >= maximumConversionMismatch {
            return .convertedOutputSilent
        }

        if snapshot.writingElapsed >= liveGraceDuration,
           snapshot.writtenDuration <
            snapshot.writingElapsed * minimumProgressRatio
        {
            return .outputStalled
        }

        return nil
    }

    static func finalIssue(
        expectedDuration: TimeInterval,
        framesWritten: Int64,
        persisted: AudioSignalSummary
    ) -> AudioCaptureHealthIssue? {
        if !persisted.hasRecordedSignal {
            return .persistedAudioSilent
        }

        if expectedDuration >= liveGraceDuration,
           persisted.duration < expectedDuration * minimumPersistedDurationRatio
        {
            return .recordingTooShort(
                expected: expectedDuration,
                actual: persisted.duration
            )
        }

        let allowedFrameDifference = max(
            Int64(2_048),
            Int64(Double(max(framesWritten, 0)) * 0.02)
        )
        if framesWritten > 0,
           abs(framesWritten - persisted.frameCount) > allowedFrameDifference
        {
            return .persistedFrameMismatch(
                written: framesWritten,
                persisted: persisted.frameCount
            )
        }

        return nil
    }
}
