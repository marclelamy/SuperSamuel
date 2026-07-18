import AVFoundation
import Foundation

struct RecordedAudio {
    let fileURL: URL
    let format: String
    let mimeType: String
}

enum AudioCaptureError: LocalizedError {
    case alreadyRecording
    case inputUnavailable
    case unsupportedFormat
    case recordingFailed(String)
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "An audio recording is already active."
        case .inputUnavailable:
            return "No audio input device is available."
        case .unsupportedFormat:
            return "The microphone format could not be converted for transcription."
        case .recordingFailed(let message):
            return "Audio recording failed: \(message)"
        case .emptyRecording:
            return "The recording did not contain any audio."
        }
    }
}

final class AudioCaptureService {
    private let fileManager: FileManager
    private let engine = AVAudioEngine()
    private let stateLock = NSLock()

    private var converter: AVAudioConverter?
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private var captureError: Error?
    private var running = false
    private var rawLevel: Float = 0
    private var displayedLevel: Float = 0

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var isRecording: Bool {
        stateLock.withLock { running }
    }

    func start(at fileURL: URL) throws {
        guard !isRecording else {
            throw AudioCaptureError.alreadyRecording
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw AudioCaptureError.inputUnavailable
        }

        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(
                from: inputFormat,
                to: targetFormat
            )
        else {
            throw AudioCaptureError.unsupportedFormat
        }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: fileURL)

        let outputFile = try AVAudioFile(
            forWriting: fileURL,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: false
        )

        stateLock.withLock {
            self.converter = converter
            self.outputFile = outputFile
            self.outputURL = fileURL
            self.captureError = nil
            self.rawLevel = 0
            self.displayedLevel = 0
            self.running = true
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.process(buffer, inputFormat: inputFormat)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            stateLock.withLock {
                running = false
                self.converter = nil
                self.outputFile = nil
                self.outputURL = nil
            }
            throw error
        }
    }

    func stop() throws -> RecordedAudio {
        let fileURL = stateLock.withLock { outputURL }
        guard let fileURL, isRecording else {
            throw AudioCaptureError.recordingFailed(
                "No recording is active."
            )
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        let error = stateLock.withLock { () -> Error? in
            running = false
            let error = captureError
            converter = nil
            outputFile = nil
            outputURL = nil
            rawLevel = 0
            displayedLevel = 0
            return error
        }

        if let error {
            throw AudioCaptureError.recordingFailed(
                error.localizedDescription
            )
        }

        let attributes = try fileManager.attributesOfItem(
            atPath: fileURL.path
        )
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size > 44 else {
            throw AudioCaptureError.emptyRecording
        }

        return RecordedAudio(
            fileURL: fileURL,
            format: "wav",
            mimeType: "audio/wav"
        )
    }

    func stopIfNeeded() -> RecordedAudio? {
        guard isRecording else {
            return nil
        }
        return try? stop()
    }

    func currentLevel() -> Float {
        stateLock.withLock {
            let target = rawLevel
            let blend: Float = target > displayedLevel ? 0.55 : 0.22
            displayedLevel += (target - displayedLevel) * blend
            return displayedLevel
        }
    }

    private func process(
        _ inputBuffer: AVAudioPCMBuffer,
        inputFormat: AVAudioFormat
    ) {
        let level = normalizedLevel(from: inputBuffer)
        stateLock.withLock {
            rawLevel = level
        }

        let state = stateLock.withLock {
            (converter, outputFile, running, captureError)
        }
        guard
            state.2,
            state.3 == nil,
            let converter = state.0,
            let outputFile = state.1
        else {
            return
        }

        let sampleRateRatio = converter.outputFormat.sampleRate /
            inputFormat.sampleRate
        let frameCapacity = AVAudioFrameCount(
            Double(inputBuffer.frameLength) * sampleRateRatio
        ) + 32
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: frameCapacity
        ) else {
            return
        }

        var sourceBuffer: AVAudioPCMBuffer? = inputBuffer
        var conversionError: NSError?
        let status = converter.convert(
            to: outputBuffer,
            error: &conversionError
        ) { _, outputStatus in
            if let buffer = sourceBuffer {
                sourceBuffer = nil
                outputStatus.pointee = .haveData
                return buffer
            }

            outputStatus.pointee = .noDataNow
            return nil
        }

        guard
            status != .error,
            conversionError == nil,
            outputBuffer.frameLength > 0
        else {
            stateLock.withLock {
                captureError = conversionError ??
                    AudioCaptureError.unsupportedFormat
            }
            return
        }

        do {
            try outputFile.write(from: outputBuffer)
        } catch {
            stateLock.withLock {
                captureError = error
            }
        }
    }

    private func normalizedLevel(
        from buffer: AVAudioPCMBuffer
    ) -> Float {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return 0
        }

        let channelCount = max(Int(buffer.format.channelCount), 1)
        var sum: Float = 0

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else {
                return 0
            }

            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for index in 0..<frameCount {
                    sum += samples[index] * samples[index]
                }
            }
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else {
                return 0
            }

            let scale = Float(Int16.max)
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for index in 0..<frameCount {
                    let sample = Float(samples[index]) / scale
                    sum += sample * sample
                }
            }
        default:
            return 0
        }

        let rms = sqrt(sum / Float(frameCount * channelCount))
        let decibels = max(-60, 20 * log10(max(rms, 0.000_001)))
        return pow(min(max((decibels + 50) / 50, 0), 1), 1.5)
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () -> T) -> T {
        lock()
        defer { unlock() }
        return operation()
    }
}
