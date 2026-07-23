import AVFoundation
import Foundation

struct RecordedAudio {
    let fileURL: URL
    let format: String
    let mimeType: String
    let signalSummary: AudioSignalSummary?
    let framesWritten: Int64?

    init(
        fileURL: URL,
        format: String,
        mimeType: String,
        signalSummary: AudioSignalSummary? = nil,
        framesWritten: Int64? = nil
    ) {
        self.fileURL = fileURL
        self.format = format
        self.mimeType = mimeType
        self.signalSummary = signalSummary
        self.framesWritten = framesWritten
    }
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
    private struct BufferSignalMetrics {
        let sampleCount: Int64
        let sumSquares: Double
        let peak: Float
        let normalizedLevel: Float
    }

    private struct AudioWriteResult {
        let frameLength: Int64
        let metrics: BufferSignalMetrics
    }

    private let fileManager: FileManager
    private let engine = AVAudioEngine()
    private let stateLock = NSLock()
    private let ioLock = NSLock()

    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var wavWriter: PCM16WAVWriter?
    private var outputURL: URL?
    private var captureError: Error?
    private var running = false
    private var rawLevel: Float = 0
    private var writtenLevel: Float = 0
    private var displayedLevel: Float = 0
    private var framesWritten: Int64 = 0
    private var recordingStartedUptime: TimeInterval = 0
    private var firstWriteUptime: TimeInterval?
    private var lastWriteUptime: TimeInterval?
    private var conversionMismatchStartedUptime: TimeInterval?
    private var tapInstalled = false

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var isRecording: Bool {
        stateLock.withLock { running }
    }

    func currentInputDeviceInfo() -> AudioInputDeviceInfo {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            return AudioInputDeviceInfo(
                name: "System Default Microphone",
                uniqueID: "system-default"
            )
        }

        return AudioInputDeviceInfo(
            name: device.localizedName,
            uniqueID: device.uniqueID
        )
    }

    @discardableResult
    func start(at fileURL: URL) throws -> AudioInputDeviceInfo {
        guard !isRecording else {
            throw AudioCaptureError.alreadyRecording
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw AudioCaptureError.inputUnavailable
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioCaptureError.unsupportedFormat
        }

        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.removeItem(at: fileURL)

        let wavWriter = try PCM16WAVWriter(
            fileURL: fileURL,
            sampleRate: 16_000,
            channelCount: 1,
            fileManager: fileManager
        )
        let startedUptime = ProcessInfo.processInfo.systemUptime

        ioLock.withLock {
            self.converter = nil
            self.targetFormat = targetFormat
            self.wavWriter = wavWriter
        }
        stateLock.withLock {
            self.outputURL = fileURL
            self.captureError = nil
            self.rawLevel = 0
            self.writtenLevel = 0
            self.displayedLevel = 0
            self.framesWritten = 0
            self.recordingStartedUptime = startedUptime
            self.firstWriteUptime = nil
            self.lastWriteUptime = nil
            self.conversionMismatchStartedUptime = nil
        }

        removeInputTapIfNeeded()
        inputNode.installTap(
            onBus: 0,
            bufferSize: 2_048,
            format: nil
        ) { [weak self] buffer, _ in
            self?.process(buffer, inputFormat: buffer.format)
        }
        stateLock.withLock {
            tapInstalled = true
        }

        do {
            engine.prepare()
            try engine.start()
            stateLock.withLock {
                running = true
            }
        } catch {
            removeInputTapIfNeeded()
            engine.stop()
            engine.reset()
            ioLock.withLock {
                self.converter = nil
                self.targetFormat = nil
                try? self.wavWriter?.close()
                self.wavWriter = nil
            }
            stateLock.withLock {
                running = false
                self.outputURL = nil
            }
            throw error
        }

        return currentInputDeviceInfo()
    }

    func stop() throws -> RecordedAudio {
        let fileURL = stateLock.withLock { outputURL }
        guard let fileURL, isRecording else {
            throw AudioCaptureError.recordingFailed(
                "No recording is active."
            )
        }

        removeInputTapIfNeeded()
        engine.stop()
        engine.reset()

        let stoppedState = ioLock.withLock {
            converter = nil
            targetFormat = nil
            var closeError: Error?
            do {
                try wavWriter?.close()
            } catch {
                closeError = error
            }
            wavWriter = nil
            return stateLock.withLock {
                let state = (
                    captureError ?? closeError,
                    framesWritten
                )
                running = false
                outputURL = nil
                rawLevel = 0
                writtenLevel = 0
                displayedLevel = 0
                firstWriteUptime = nil
                lastWriteUptime = nil
                conversionMismatchStartedUptime = nil
                return state
            }
        }

        if let error = stoppedState.0 {
            throw AudioCaptureError.recordingFailed(
                error.localizedDescription
            )
        }

        let summary: AudioSignalSummary
        do {
            summary = try PCM16WAVFile.summarize(at: fileURL)
        } catch {
            throw AudioCaptureError.recordingFailed(
                "The saved WAV could not be verified: \(error.localizedDescription)"
            )
        }

        guard summary.sizeBytes > 44, summary.frameCount > 0 else {
            throw AudioCaptureError.emptyRecording
        }

        return RecordedAudio(
            fileURL: fileURL,
            format: "wav",
            mimeType: "audio/wav",
            signalSummary: summary,
            framesWritten: stoppedState.1
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
            let target = writtenLevel
            let blend: Float = target > displayedLevel ? 0.55 : 0.22
            displayedLevel += (target - displayedLevel) * blend
            return displayedLevel
        }
    }

    func healthSnapshot(elapsed: TimeInterval) -> AudioCaptureHealthSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        let state = stateLock.withLock {
            (
                rawLevel: rawLevel,
                writtenLevel: writtenLevel,
                framesWritten: framesWritten,
                recordingStartedUptime: recordingStartedUptime,
                firstWriteUptime: firstWriteUptime,
                lastWriteUptime: lastWriteUptime,
                conversionMismatchStartedUptime:
                    conversionMismatchStartedUptime,
                outputURL: outputURL,
                captureError: captureError
            )
        }
        let writeReference =
            state.lastWriteUptime ?? state.recordingStartedUptime
        let writingElapsed = state.firstWriteUptime.map {
            max(0, now - $0)
        } ?? 0
        let mismatchDuration = state.conversionMismatchStartedUptime.map {
            max(0, now - $0)
        } ?? 0
        let fileSize = state.outputURL.map(fileSize(at:)) ?? 0

        return AudioCaptureHealthSnapshot(
            elapsed: elapsed,
            rawLevel: state.rawLevel,
            writtenLevel: state.writtenLevel,
            framesWritten: state.framesWritten,
            sampleRate: 16_000,
            lastWriteAge: max(0, now - writeReference),
            writingElapsed: writingElapsed,
            conversionMismatchDuration: mismatchDuration,
            fileSizeBytes: fileSize,
            failureDescription: state.captureError?.localizedDescription
        )
    }

    private func process(
        _ inputBuffer: AVAudioPCMBuffer,
        inputFormat: AVAudioFormat
    ) {
        let inputMetrics = signalMetrics(from: inputBuffer)
        stateLock.withLock {
            rawLevel = inputMetrics.normalizedLevel
        }

        let shouldWrite = stateLock.withLock {
            running && captureError == nil
        }
        guard shouldWrite else {
            return
        }

        do {
            try ioLock.withLock {
                guard
                    let targetFormat,
                    let wavWriter
                else {
                    return
                }

                guard let result = try convertAndWrite(
                    inputBuffer,
                    inputFormat: inputFormat,
                    targetFormat: targetFormat,
                    wavWriter: wavWriter
                ) else {
                    return
                }

                let now = ProcessInfo.processInfo.systemUptime
                stateLock.withLock {
                    framesWritten += result.frameLength
                    writtenLevel = result.metrics.normalizedLevel
                    firstWriteUptime = firstWriteUptime ?? now
                    lastWriteUptime = now

                    let inputHasSignal =
                        inputMetrics.normalizedLevel >= 0.025
                    let convertedOutputIsSilent =
                        result.metrics.peak <= 0.000_01
                    if inputHasSignal && convertedOutputIsSilent {
                        conversionMismatchStartedUptime =
                            conversionMismatchStartedUptime ?? now
                    } else {
                        conversionMismatchStartedUptime = nil
                    }
                }
            }
        } catch {
            stateLock.withLock {
                captureError = error
            }
        }
    }

    private func convertAndWrite(
        _ inputBuffer: AVAudioPCMBuffer,
        inputFormat: AVAudioFormat,
        targetFormat: AVAudioFormat,
        wavWriter: PCM16WAVWriter
    ) throws -> AudioWriteResult? {
        let converter: AVAudioConverter
        if let existingConverter = self.converter,
           formatsMatch(
               existingConverter.inputFormat,
               inputFormat
           )
        {
            converter = existingConverter
        } else {
            guard let newConverter = AVAudioConverter(
                from: inputFormat,
                to: targetFormat
            ) else {
                throw AudioCaptureError.unsupportedFormat
            }
            self.converter = newConverter
            converter = newConverter
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
            throw AudioCaptureError.unsupportedFormat
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

        if status == .error || conversionError != nil {
            throw conversionError ?? AudioCaptureError.unsupportedFormat
        }

        guard outputBuffer.frameLength > 0 else {
            return nil
        }

        let outputMetrics = signalMetrics(from: outputBuffer)
        try wavWriter.write(from: outputBuffer)
        return AudioWriteResult(
            frameLength: Int64(outputBuffer.frameLength),
            metrics: outputMetrics
        )
    }

    private func removeInputTapIfNeeded() {
        let shouldRemove = stateLock.withLock {
            guard tapInstalled else {
                return false
            }
            tapInstalled = false
            return true
        }

        if shouldRemove {
            engine.inputNode.removeTap(onBus: 0)
        }
    }

    private func formatsMatch(
        _ lhs: AVAudioFormat,
        _ rhs: AVAudioFormat
    ) -> Bool {
        lhs.sampleRate == rhs.sampleRate &&
            lhs.channelCount == rhs.channelCount &&
            lhs.commonFormat == rhs.commonFormat &&
            lhs.isInterleaved == rhs.isInterleaved
    }

    private func signalMetrics(
        from buffer: AVAudioPCMBuffer
    ) -> BufferSignalMetrics {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return BufferSignalMetrics(
                sampleCount: 0,
                sumSquares: 0,
                peak: 0,
                normalizedLevel: 0
            )
        }

        let channelCount = max(Int(buffer.format.channelCount), 1)
        var sumSquares: Double = 0
        var peak: Float = 0

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else {
                return emptyMetrics
            }

            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for index in 0..<frameCount {
                    let sample = samples[index]
                    sumSquares += Double(sample * sample)
                    peak = max(peak, abs(sample))
                }
            }
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else {
                return emptyMetrics
            }

            let scale = Float(Int16.max)
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for index in 0..<frameCount {
                    let sample = Float(samples[index]) / scale
                    sumSquares += Double(sample * sample)
                    peak = max(peak, abs(sample))
                }
            }
        default:
            return emptyMetrics
        }

        let sampleCount = Int64(frameCount * channelCount)
        let rms = sampleCount > 0
            ? Float(sqrt(sumSquares / Double(sampleCount)))
            : 0

        return BufferSignalMetrics(
            sampleCount: sampleCount,
            sumSquares: sumSquares,
            peak: peak,
            normalizedLevel: normalizedLevel(fromRMS: rms)
        )
    }

    private var emptyMetrics: BufferSignalMetrics {
        BufferSignalMetrics(
            sampleCount: 0,
            sumSquares: 0,
            peak: 0,
            normalizedLevel: 0
        )
    }

    private func normalizedLevel(fromRMS rms: Float) -> Float {
        let decibels = max(-60, 20 * log10(max(rms, 0.000_001)))
        return pow(min(max((decibels + 50) / 50, 0), 1), 1.5)
    }

    private func fileSize(at url: URL) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
