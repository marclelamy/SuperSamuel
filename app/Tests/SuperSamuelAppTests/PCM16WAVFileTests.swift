import AVFoundation
import XCTest
@testable import SuperSamuelApp

final class PCM16WAVFileTests: XCTestCase {
    func testWriterCanBeVerifiedImmediatelyAfterClose() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 1_600
            )
        )
        buffer.frameLength = 1_600

        let samples = try XCTUnwrap(buffer.int16ChannelData?[0])
        for index in 0..<Int(buffer.frameLength) {
            samples[index] = index.isMultiple(of: 2) ? 12_000 : -12_000
        }

        let writer = try PCM16WAVWriter(fileURL: fileURL)
        try writer.write(from: buffer)
        try writer.close()

        let summary = try PCM16WAVFile.summarize(at: fileURL)
        XCTAssertEqual(summary.frameCount, 1_600)
        XCTAssertEqual(summary.sampleCount, 1_600)
        XCTAssertEqual(summary.duration, 0.1, accuracy: 0.000_1)
        XCTAssertGreaterThan(summary.rms, 0.3)
        XCTAssertGreaterThan(summary.peak, 0.3)
        XCTAssertEqual(summary.sizeBytes, 3_244)

        let systemReader = try AVAudioFile(forReading: fileURL)
        XCTAssertEqual(systemReader.length, 1_600)
    }

    func testSummaryDetectsDigitalSilence() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).wav")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 800
            )
        )
        buffer.frameLength = 800
        memset(
            try XCTUnwrap(buffer.int16ChannelData?[0]),
            0,
            Int(buffer.frameLength) * MemoryLayout<Int16>.size
        )

        let writer = try PCM16WAVWriter(fileURL: fileURL)
        try writer.write(from: buffer)
        try writer.close()

        let summary = try PCM16WAVFile.summarize(at: fileURL)
        XCTAssertEqual(summary.frameCount, 800)
        XCTAssertEqual(summary.rms, 0)
        XCTAssertEqual(summary.peak, 0)
    }
}
