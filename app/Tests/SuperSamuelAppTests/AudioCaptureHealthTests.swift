import XCTest
@testable import SuperSamuelApp

final class AudioCaptureHealthTests: XCTestCase {
    func testLiveHealthAcceptsAudioThatIsBeingWritten() {
        let snapshot = AudioCaptureHealthSnapshot(
            elapsed: 10,
            rawLevel: 0.4,
            writtenLevel: 0.38,
            framesWritten: 158_000,
            sampleRate: 16_000,
            lastWriteAge: 0.03,
            conversionMismatchDuration: 0,
            fileSizeBytes: 316_044,
            failureDescription: nil
        )

        XCTAssertNil(AudioCaptureHealthPolicy.liveIssue(for: snapshot))
    }

    func testLiveHealthRejectsRawSignalConvertedToSilence() {
        let snapshot = AudioCaptureHealthSnapshot(
            elapsed: 4,
            rawLevel: 0.5,
            writtenLevel: 0,
            framesWritten: 64_000,
            sampleRate: 16_000,
            lastWriteAge: 0.03,
            conversionMismatchDuration: 1.1,
            fileSizeBytes: 128_044,
            failureDescription: nil
        )

        XCTAssertEqual(
            AudioCaptureHealthPolicy.liveIssue(for: snapshot),
            .convertedOutputSilent
        )
    }

    func testLiveHealthRejectsStalledWrites() {
        let snapshot = AudioCaptureHealthSnapshot(
            elapsed: 5,
            rawLevel: 0.5,
            writtenLevel: 0.4,
            framesWritten: 20_000,
            sampleRate: 16_000,
            lastWriteAge: 2,
            conversionMismatchDuration: 0,
            fileSizeBytes: 40_044,
            failureDescription: nil
        )

        XCTAssertEqual(
            AudioCaptureHealthPolicy.liveIssue(for: snapshot),
            .outputStalled
        )
    }

    func testFinalHealthRejectsPersistedDigitalSilence() {
        let summary = AudioSignalSummary(
            frameCount: 160_000,
            sampleCount: 160_000,
            duration: 10,
            rms: 0,
            peak: 0,
            sizeBytes: 320_044
        )

        XCTAssertEqual(
            AudioCaptureHealthPolicy.finalIssue(
                expectedDuration: 10,
                framesWritten: 160_000,
                persisted: summary
            ),
            .persistedAudioSilent
        )
    }

    func testFinalHealthRejectsIncompleteFile() {
        let summary = AudioSignalSummary(
            frameCount: 64_000,
            sampleCount: 64_000,
            duration: 4,
            rms: 0.1,
            peak: 0.4,
            sizeBytes: 128_044
        )

        XCTAssertEqual(
            AudioCaptureHealthPolicy.finalIssue(
                expectedDuration: 10,
                framesWritten: 64_000,
                persisted: summary
            ),
            .recordingTooShort(expected: 10, actual: 4)
        )
    }

    func testFinalHealthAcceptsAudibleCompleteFile() {
        let summary = AudioSignalSummary(
            frameCount: 159_500,
            sampleCount: 159_500,
            duration: 9.97,
            rms: 0.08,
            peak: 0.6,
            sizeBytes: 319_044
        )

        XCTAssertNil(
            AudioCaptureHealthPolicy.finalIssue(
                expectedDuration: 10,
                framesWritten: 160_000,
                persisted: summary
            )
        )
    }
}
