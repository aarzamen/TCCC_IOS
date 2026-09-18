import AVFoundation
import XCTest
@testable import TCCC_IOS

final class MicrophoneInputProcessorTests: XCTestCase {
    func testFloatStereoPlanarAndInterleavedShareGainAndMeterProcessedAudio() throws {
        for interleaved in [false, true] {
            let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000, channels: 2, interleaved: interleaved))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
            buffer.frameLength = 160
            for audio in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
                let data = try XCTUnwrap(audio.mData).assumingMemoryBound(to: Float.self)
                let count = 160 * Int(audio.mNumberChannels)
                for i in 0..<count { data[i] = i.isMultiple(of: 2) ? 2 : -1 }
            }
            var processor = MicrophoneInputProcessor(mode: .systemAutomatic)
            let report = processor.process(buffer)
            var energy: Double = 0
            var count = 0
            for audio in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
                let data = try XCTUnwrap(audio.mData).assumingMemoryBound(to: Float.self)
                for i in 0..<(160 * Int(audio.mNumberChannels)) {
                    XCTAssertLessThanOrEqual(abs(data[i]), 0.89001)
                    XCTAssertEqual(data[i], i.isMultiple(of: 2) ? 0.89 : -0.445, accuracy: 0.0001)
                    energy += Double(data[i] * data[i]); count += 1
                }
            }
            XCTAssertEqual(report.rms, Float(sqrt(energy / Double(count))), accuracy: 0.0001)
            XCTAssertTrue(report.shouldPublish)
        }
    }

    func testNonfiniteFloatSamplesAreSilencedBeforeMeterAndGain() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        let data = try XCTUnwrap(buffer.floatChannelData)[0]
        data[0] = .nan; data[1] = .infinity; data[2] = -.infinity; data[3] = 0.1
        var processor = MicrophoneInputProcessor(mode: .systemAutomatic)
        let report = processor.process(buffer)
        for index in 0..<3 { XCTAssertEqual(data[index], 0) }
        XCTAssertEqual(report.rms, 0.05, accuracy: 0.0001)
        XCTAssertTrue(report.gainDb.isFinite)
    }

    func testInt16ExtremaAreLimitedWithoutWraparound() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16,
            sampleRate: 16_000, channels: 2, interleaved: true))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 160))
        buffer.frameLength = 160
        let audio = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)[0]
        let data = try XCTUnwrap(audio.mData).assumingMemoryBound(to: Int16.self)
        for i in 0..<320 { data[i] = i.isMultiple(of: 2) ? .max : .min }
        var processor = MicrophoneInputProcessor(mode: .softwareAutomatic)
        let report = processor.process(buffer)
        for i in 0..<320 {
            XCTAssertLessThanOrEqual(abs(Int(data[i])), 29_164)
            XCTAssertEqual(data[i] > 0, i.isMultiple(of: 2))
        }
        XCTAssertTrue(report.rms.isFinite)
    }

    func testMeterPublishesAtMostTenTimesPerSecondAfterFirstBuffer() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 320))
        buffer.frameLength = 320
        buffer.floatChannelData![0].initialize(repeating: 0, count: 320)
        var processor = MicrophoneInputProcessor()
        XCTAssertTrue(processor.process(buffer).shouldPublish)
        var publications = 0
        for _ in 0..<50 { if processor.process(buffer).shouldPublish { publications += 1 } }
        XCTAssertEqual(publications, 10)
    }
}
