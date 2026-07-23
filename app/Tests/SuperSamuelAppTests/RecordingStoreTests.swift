import AVFoundation
import XCTest
@testable import SuperSamuelApp

@MainActor
final class RecordingStoreTests: XCTestCase {
    func testAudioChunksExcludeSilentTail() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let audible = try addChunk(
            to: fixture.store,
            sessionID: fixture.session.id,
            sample: 12_000
        )
        _ = try addChunk(
            to: fixture.store,
            sessionID: fixture.session.id,
            sample: 0
        )

        let session = try fixture.store.load(fixture.session.id)
        let chunks = try fixture.store.audioChunks(for: session)

        XCTAssertEqual(chunks.map(\.0.id), [audible.id])
    }

    func testDiscardCurrentChunkKeepsEarlierUsableAudio() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let audible = try addChunk(
            to: fixture.store,
            sessionID: fixture.session.id,
            sample: 12_000
        )
        let emptyURL = try fixture.store.beginChunk(in: fixture.session.id)
        let writer = try PCM16WAVWriter(fileURL: emptyURL)
        try writer.close()

        XCTAssertTrue(
            try fixture.store
                .discardCurrentChunkIfPreviousUsableAudioExists(
                    in: fixture.session.id
                )
        )

        let session = try fixture.store.load(fixture.session.id)
        XCTAssertEqual(session.chunks.map(\.id), [audible.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyURL.path))
    }

    func testDiscardCurrentChunkDoesNotDeleteOnlyChunk() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let emptyURL = try fixture.store.beginChunk(in: fixture.session.id)
        let writer = try PCM16WAVWriter(fileURL: emptyURL)
        try writer.close()

        XCTAssertFalse(
            try fixture.store
                .discardCurrentChunkIfPreviousUsableAudioExists(
                    in: fixture.session.id
                )
        )

        let session = try fixture.store.load(fixture.session.id)
        XCTAssertEqual(session.chunks.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: emptyURL.path))
    }

    private func makeFixture() throws -> (
        root: URL,
        store: RecordingStore,
        session: RecordingSession
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = RecordingStore(rootDirectory: root)
        let session = try store.createSession(
            cleanup: PersistedCleanupOptions(
                isEnabled: false,
                model: "",
                prompt: ""
            )
        )
        return (root, store, session)
    }

    private func addChunk(
        to store: RecordingStore,
        sessionID: UUID,
        sample: Int16
    ) throws -> RecordingChunk {
        let fileURL = try store.beginChunk(in: sessionID)
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
            samples[index] = sample
        }

        let writer = try PCM16WAVWriter(fileURL: fileURL)
        try writer.write(from: buffer)
        try writer.close()

        let summary = try PCM16WAVFile.summarize(at: fileURL)
        let recordedAudio = RecordedAudio(
            fileURL: fileURL,
            format: "wav",
            mimeType: "audio/wav",
            signalSummary: summary,
            framesWritten: summary.frameCount
        )
        try store.finishCurrentChunk(
            in: sessionID,
            duration: summary.duration,
            recordedAudio: recordedAudio
        )

        return try XCTUnwrap(store.load(sessionID).chunks.last)
    }
}
