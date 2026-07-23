import AVFoundation
import Foundation

enum PCM16WAVError: LocalizedError {
    case couldNotCreateFile
    case writerClosed
    case unsupportedBuffer
    case fileTooLarge
    case invalidFile

    var errorDescription: String? {
        switch self {
        case .couldNotCreateFile:
            return "The WAV file could not be created."
        case .writerClosed:
            return "The WAV writer is already closed."
        case .unsupportedBuffer:
            return "The converted audio buffer is not 16-bit mono PCM."
        case .fileTooLarge:
            return "The WAV file exceeded the supported size."
        case .invalidFile:
            return "The saved WAV header or audio data is invalid."
        }
    }
}

final class PCM16WAVWriter {
    private let sampleRate: UInt32
    private let channelCount: UInt16
    private var fileHandle: FileHandle?
    private var dataByteCount: UInt32 = 0

    init(
        fileURL: URL,
        sampleRate: UInt32 = 16_000,
        channelCount: UInt16 = 1,
        fileManager: FileManager = .default
    ) throws {
        self.sampleRate = sampleRate
        self.channelCount = channelCount

        guard fileManager.createFile(
            atPath: fileURL.path,
            contents: PCM16WAVFile.header(
                sampleRate: sampleRate,
                channelCount: channelCount,
                dataByteCount: 0
            )
        ) else {
            throw PCM16WAVError.couldNotCreateFile
        }

        let fileHandle = try FileHandle(forWritingTo: fileURL)
        try fileHandle.seekToEnd()
        self.fileHandle = fileHandle
    }

    func write(from buffer: AVAudioPCMBuffer) throws {
        guard
            let fileHandle,
            buffer.format.commonFormat == .pcmFormatInt16,
            buffer.format.channelCount == channelCount,
            channelCount == 1,
            let samples = buffer.int16ChannelData?[0]
        else {
            throw fileHandle == nil
                ? PCM16WAVError.writerClosed
                : PCM16WAVError.unsupportedBuffer
        }

        let byteCount = Int(buffer.frameLength) *
            MemoryLayout<Int16>.size
        guard UInt64(dataByteCount) + UInt64(byteCount) <= UInt64(UInt32.max) else {
            throw PCM16WAVError.fileTooLarge
        }

        try fileHandle.write(
            contentsOf: Data(
                bytes: samples,
                count: byteCount
            )
        )
        dataByteCount += UInt32(byteCount)
    }

    func close() throws {
        guard let fileHandle else {
            return
        }

        try fileHandle.seek(toOffset: 0)
        try fileHandle.write(
            contentsOf: PCM16WAVFile.header(
                sampleRate: sampleRate,
                channelCount: channelCount,
                dataByteCount: dataByteCount
            )
        )
        try fileHandle.synchronize()
        try fileHandle.close()
        self.fileHandle = nil
    }

    deinit {
        try? close()
    }
}

enum PCM16WAVFile {
    static func summarize(at fileURL: URL) throws -> AudioSignalSummary {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard
            data.count >= 44,
            data.ascii(at: 0, count: 4) == "RIFF",
            data.ascii(at: 8, count: 4) == "WAVE"
        else {
            throw PCM16WAVError.invalidFile
        }

        var offset = 12
        var channelCount: UInt16?
        var sampleRate: UInt32?
        var bitsPerSample: UInt16?
        var audioFormat: UInt16?
        var audioRange: Range<Int>?

        while offset + 8 <= data.count {
            let chunkID = data.ascii(at: offset, count: 4)
            let chunkSize = Int(data.littleEndianUInt32(at: offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + chunkSize
            guard payloadEnd <= data.count else {
                throw PCM16WAVError.invalidFile
            }

            if chunkID == "fmt ", chunkSize >= 16 {
                audioFormat = data.littleEndianUInt16(at: payloadStart)
                channelCount = data.littleEndianUInt16(at: payloadStart + 2)
                sampleRate = data.littleEndianUInt32(at: payloadStart + 4)
                bitsPerSample = data.littleEndianUInt16(at: payloadStart + 14)
            } else if chunkID == "data" {
                audioRange = payloadStart..<payloadEnd
                break
            }

            offset = payloadEnd + (chunkSize % 2)
        }

        guard
            audioFormat == 1,
            let channelCount,
            channelCount > 0,
            let sampleRate,
            sampleRate > 0,
            bitsPerSample == 16,
            let audioRange,
            audioRange.count >= MemoryLayout<Int16>.size
        else {
            throw PCM16WAVError.invalidFile
        }

        let sampleCount = audioRange.count / MemoryLayout<Int16>.size
        var sumSquares: Double = 0
        var peak: Float = 0

        data.withUnsafeBytes { rawBytes in
            for sampleIndex in 0..<sampleCount {
                let byteOffset = audioRange.lowerBound +
                    (sampleIndex * MemoryLayout<Int16>.size)
                let bitPattern =
                    UInt16(rawBytes[byteOffset]) |
                    (UInt16(rawBytes[byteOffset + 1]) << 8)
                let sample = Float(
                    Int16(bitPattern: bitPattern)
                ) / Float(Int16.max)
                sumSquares += Double(sample * sample)
                peak = max(peak, abs(sample))
            }
        }

        let frameCount = Int64(sampleCount) / Int64(channelCount)
        let rms = sampleCount > 0
            ? Float(sqrt(sumSquares / Double(sampleCount)))
            : 0

        return AudioSignalSummary(
            frameCount: frameCount,
            sampleCount: Int64(sampleCount),
            duration: Double(frameCount) / Double(sampleRate),
            rms: rms,
            peak: peak,
            sizeBytes: Int64(data.count)
        )
    }

    static func header(
        sampleRate: UInt32,
        channelCount: UInt16,
        dataByteCount: UInt32
    ) -> Data {
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt16(bitsPerSample / 8)
        let blockAlign = channelCount * bytesPerSample
        let byteRate = sampleRate * UInt32(blockAlign)

        var data = Data()
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(36) + dataByteCount)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channelCount)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.appendASCII("data")
        data.appendLittleEndian(dataByteCount)
        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) {
            append(contentsOf: $0)
        }
    }

    func ascii(at offset: Int, count: Int) -> String? {
        guard offset >= 0, count >= 0, offset + count <= self.count else {
            return nil
        }
        return String(data: self[offset..<(offset + count)], encoding: .ascii)
    }

    func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) |
            (UInt16(self[offset + 1]) << 8)
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }
}
