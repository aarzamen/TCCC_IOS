import AVFoundation
import XCTest
@testable import TCCC_IOS

final class GraniteAudioCaptureTests: XCTestCase {
    private actor Writer {
        var received: [Float] = []
        var waiting: CheckedContinuation<Void, Never>?
        var entered: [CheckedContinuation<Void, Never>] = []
        let shouldFail: Bool

        init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

        func write(_ captured: GraniteAudioCapture.PCM) async throws {
            let buffer = captured.buffer
            received.append(buffer.floatChannelData![0][0])
            if received.count == 1 {
                await withCheckedContinuation { continuation in
                    waiting = continuation
                    entered.forEach { $0.resume() }
                    entered.removeAll()
                }
            }
            if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
        }

        func waitUntilSuspended() async {
            if waiting != nil { return }
            await withCheckedContinuation { entered.append($0) }
        }
        func release() { waiting?.resume(); waiting = nil }
        func values() -> [Float] { received }
    }

    private func buffer(_ value: Float, frames: AVAudioFrameCount = 16,
                        rate: Double = 16_000, channels: AVAudioChannelCount = 1) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        result.frameLength = frames
        for channel in 0..<Int(channels) {
            for index in 0..<Int(frames) { result.floatChannelData![channel][index] = value }
        }
        return result
    }

    func testStopDrainsAcceptedBuffersInOrderBeforeFinishing() async {
        let writer = Writer()
        let capture = GraniteAudioCapture(maxQueuedFrames: 64) { try await writer.write($0) }
        XCTAssertTrue(capture.enqueue(buffer(1), capturedAt: 10))
        await writer.waitUntilSuspended()
        XCTAssertTrue(capture.enqueue(buffer(2), capturedAt: 11))
        XCTAssertTrue(capture.enqueue(buffer(3), capturedAt: 12))
        capture.closeAdmission()
        XCTAssertFalse(capture.enqueue(buffer(4), capturedAt: 13))
        let closing = Task { await capture.closeAndDrain() }
        await writer.release()
        let outcome = await closing.value
        let received = await writer.values()
        XCTAssertEqual(received, [1, 2, 3])
        XCTAssertNil(outcome.issue)
        XCTAssertEqual(outcome.requestStartedAt, 10)
    }

    func testOverloadCountsSuspendedWriteAndCannotReportSuccess() async {
        let writer = Writer()
        let capture = GraniteAudioCapture(maxQueuedFrames: 32) { try await writer.write($0) }
        XCTAssertTrue(capture.enqueue(buffer(1), capturedAt: 10))
        await writer.waitUntilSuspended()
        XCTAssertTrue(capture.enqueue(buffer(2), capturedAt: 11))
        XCTAssertFalse(capture.enqueue(buffer(3), capturedAt: 12))
        await writer.release()
        let outcome = await capture.closeAndDrain()
        XCTAssertNotNil(outcome.issue)
        XCTAssertEqual(outcome.requestStartedAt, 10)
    }

    func testCancelledStopWaiterStillDrainsAcceptedArchiveWrites() async {
        let writer = Writer()
        let capture = GraniteAudioCapture(maxQueuedFrames: 64) { try await writer.write($0) }
        XCTAssertTrue(capture.enqueue(buffer(1), capturedAt: 10))
        await writer.waitUntilSuspended()
        XCTAssertTrue(capture.enqueue(buffer(2), capturedAt: 11))
        capture.closeAdmission()
        let stop = Task { await capture.closeAndDrain() }
        stop.cancel()
        await writer.release()
        let outcome = await stop.value
        let received = await writer.values()
        XCTAssertEqual(received, [1, 2])
        XCTAssertNil(outcome.issue)
    }

    func testWriteFailureIsRetainedAndStopsFollowingWrites() async {
        let writer = Writer(shouldFail: true)
        let capture = GraniteAudioCapture(maxQueuedFrames: 64) { try await writer.write($0) }
        XCTAssertTrue(capture.enqueue(buffer(1), capturedAt: 10))
        await writer.waitUntilSuspended()
        XCTAssertTrue(capture.enqueue(buffer(2), capturedAt: 11))
        await writer.release()
        let outcome = await capture.closeAndDrain()
        XCTAssertNotNil(outcome.issue)
        let received = await writer.values()
        XCTAssertEqual(received, [1])
    }

    func testCopyFailureAfterAdmissionClosedCannotBecomeSuccess() async {
        let capture = GraniteAudioCapture(maxQueuedFrames: 64) { _ in }
        capture.closeAdmission()
        capture.fail("Synthetic copy failure")
        let outcome = await capture.closeAndDrain()
        XCTAssertNotNil(outcome.issue)
    }

    func testInvalidTimestampRejectsAudioWithoutClaimingSuccess() async {
        let capture = GraniteAudioCapture(maxQueuedFrames: 64) { _ in }
        XCTAssertFalse(capture.enqueue(buffer(1), capturedAt: .infinity))
        let outcome = await capture.closeAndDrain()
        XCTAssertNotNil(outcome.issue)
        XCTAssertNil(outcome.requestStartedAt)
    }

    func testHardwareFormatsProduceAACArchiveWithCorrectDuration() throws {
        for (rate, channels) in [(48_000.0, AVAudioChannelCount(1)), (44_100.0, AVAudioChannelCount(2))] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
            defer { try? FileManager.default.removeItem(at: url) }
            // Production pre-creates its protected file before opening AVAudioFile.
            try Data().write(to: url)
            let input = buffer(0.1, frames: 1024, rate: rate, channels: channels)
            var file: AVAudioFile? = try AVAudioFile(forWriting: url,
                settings: AudioCaptureConfig.aacOutputSettings,
                commonFormat: .pcmFormatFloat32, interleaved: false)
            var writer: PCMArchiveWriter? = try PCMArchiveWriter(inputFormat: input.format, audioFile: file!)
            for _ in 0..<150 { try writer!.append(input) }
            writer = nil
            file = nil
            let archive = try AVAudioFile(forReading: url)
            XCTAssertEqual(archive.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatMPEG4AAC)
            XCTAssertEqual(archive.processingFormat.sampleRate, 16_000)
            XCTAssertEqual(archive.processingFormat.channelCount, 1)
            XCTAssertEqual(Double(archive.length) / 16_000, 153_600 / rate, accuracy: 0.08)
            XCTAssertGreaterThan(archive.length, 40_000)
        }
    }

    func testArchiveWriteErrorsPropagate() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let input = buffer(0.1, frames: 1024, rate: 48_000)
        var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: ParakeetPCMResampler.outputFormat.settings)
        try file!.write(from: buffer(0.1, frames: 1024))
        file = nil
        let readOnly = try AVAudioFile(forReading: url)
        let writer = try PCMArchiveWriter(inputFormat: input.format, audioFile: readOnly)
        XCTAssertThrowsError(try writer.append(input))
    }
}
