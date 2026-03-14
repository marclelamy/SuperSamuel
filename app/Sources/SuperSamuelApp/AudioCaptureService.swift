import AVFoundation
import Foundation

enum AudioCaptureError: LocalizedError {
    case inputUnavailable
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            return "No audio input device is available."
        case .unsupportedFormat:
            return "Unsupported microphone format."
        }
    }
}

final class AudioCaptureService {
    var onChunk: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let processingQueue = DispatchQueue(label: "supersamuel.audio.processing")
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var chunkTimer: DispatchSourceTimer?
    private var pendingBytes = Data()
    private var isRunning = false
    private var waveformModel = WaveformModel()

    func start() throws {
        guard !isRunning else {
            return
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw AudioCaptureError.inputUnavailable
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioCaptureError.unsupportedFormat
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.unsupportedFormat
        }

        self.converter = converter
        self.targetFormat = targetFormat
        waveformModel.reset()
        pendingBytes.removeAll(keepingCapacity: true)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer, inputFormat: inputFormat)
        }

        engine.prepare()
        try engine.start()
        startChunkTimer()
        isRunning = true
    }

    func stop() {
        guard isRunning else {
            return
        }

        isRunning = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        chunkTimer?.cancel()
        chunkTimer = nil

        processingQueue.async { [weak self] in
            self?.pendingBytes.removeAll(keepingCapacity: true)
        }
    }

    private func startChunkTimer() {
        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.flushPendingBytesLocked()
        }
        timer.resume()
        chunkTimer = timer
    }

    private func processInputBuffer(_ inputBuffer: AVAudioPCMBuffer, inputFormat: AVAudioFormat) {
        let metrics = computeMetrics(from: inputBuffer)
        let level = waveformModel.process(metrics)
        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(level)
        }

        guard let converter, let targetFormat else {
            return
        }

        let sampleRateRatio = targetFormat.sampleRate / inputFormat.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * sampleRateRatio) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return
        }

        var localInputBuffer: AVAudioPCMBuffer? = inputBuffer
        var error: NSError?
        _ = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if let buffer = localInputBuffer {
                outStatus.pointee = .haveData
                localInputBuffer = nil
                return buffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }

        guard error == nil, outputBuffer.frameLength > 0 else {
            return
        }

        guard let channelData = outputBuffer.int16ChannelData else {
            return
        }

        let frameCount = Int(outputBuffer.frameLength)
        let byteCount = frameCount * MemoryLayout<Int16>.size
        let data = Data(bytes: channelData[0], count: byteCount)

        processingQueue.async { [weak self] in
            self?.pendingBytes.append(data)
        }
    }

    private func flushPendingBytesLocked() {
        guard !pendingBytes.isEmpty else {
            return
        }

        let chunk = pendingBytes
        pendingBytes.removeAll(keepingCapacity: true)
        onChunk?(chunk)
    }

    private func computeMetrics(from buffer: AVAudioPCMBuffer) -> WaveformInputMetrics {
        let count = Int(buffer.frameLength)
        guard count > 0 else {
            return WaveformInputMetrics(rms: 0, peak: 0, sampleDuration: 0.05)
        }

        let channelCount = max(Int(buffer.format.channelCount), 1)
        var sum: Float = 0
        var peak: Float = 0

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData else {
                return WaveformInputMetrics(rms: 0, peak: 0, sampleDuration: 0.05)
            }
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for index in 0..<count {
                    let sample = samples[index]
                    let magnitude = abs(sample)
                    sum += sample * sample
                    peak = max(peak, magnitude)
                }
            }
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData else {
                return WaveformInputMetrics(rms: 0, peak: 0, sampleDuration: 0.05)
            }
            let scale = Float(Int16.max)
            for channel in 0..<channelCount {
                let samples = channelData[channel]
                for index in 0..<count {
                    let sample = Float(samples[index]) / scale
                    let magnitude = abs(sample)
                    sum += sample * sample
                    peak = max(peak, magnitude)
                }
            }
        default:
            return WaveformInputMetrics(rms: 0, peak: 0, sampleDuration: 0.05)
        }

        let totalSamples = Float(count * channelCount)
        let rms = sqrt(sum / totalSamples)
        let sampleDuration = Float(Double(buffer.frameLength) / buffer.format.sampleRate)

        return WaveformInputMetrics(
            rms: rms,
            peak: peak,
            sampleDuration: sampleDuration
        )
    }
}
