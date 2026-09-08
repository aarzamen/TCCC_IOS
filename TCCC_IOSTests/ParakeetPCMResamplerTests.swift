import AVFoundation
import XCTest
@testable import TCCC_IOS

final class ParakeetPCMResamplerTests: XCTestCase {
    func testRepeated48kMonoBuffersPreserveDurationBeyondFirstTap() throws {
        try assertContinuousConversion(sampleRate: 48_000, channels: 1)
    }

    func testRepeated44100StereoBuffersPreserveDurationBeyondFirstTap() throws {
        try assertContinuousConversion(sampleRate: 44_100, channels: 2)
    }

    private func assertContinuousConversion(sampleRate: Double, channels: AVAudioChannelCount,
                                            file: StaticString = #filePath, line: UInt = #line) throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate, channels: channels, interleaved: false))
        // Deliberately keep one converter for every tap. Recreating it would
        // conceal the permanent drain caused by endOfStream after the first tap.
        let resampler = try XCTUnwrap(ParakeetPCMResampler(inputFormat: format))
        let batchCount = 150
        let framesPerBatch: AVAudioFrameCount = 1_024
        var totalOutputFrames = 0
        var energy: Double = 0
        var laterNonemptyBatches = 0
        for batch in 0..<batchCount {
            let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerBatch))
            input.frameLength = framesPerBatch
            let channelsData = try XCTUnwrap(input.floatChannelData)
            for channel in 0..<Int(channels) {
                for frame in 0..<Int(framesPerBatch) {
                    let position = batch * Int(framesPerBatch) + frame
                    channelsData[channel][frame] = Float(0.25 * sin(2 * .pi * 440 * Double(position) / sampleRate))
                }
            }
            let output = try resampler.convert(input)
            XCTAssertEqual(output.format.sampleRate, 16_000, file: file, line: line)
            XCTAssertEqual(output.format.channelCount, 1, file: file, line: line)
            XCTAssertEqual(output.format.commonFormat, .pcmFormatFloat32, file: file, line: line)
            XCTAssertFalse(output.format.isInterleaved, file: file, line: line)
            if batch >= batchCount - 10, output.frameLength > 0 { laterNonemptyBatches += 1 }
            totalOutputFrames += Int(output.frameLength)
            if let samples = output.floatChannelData?[0] {
                for frame in 0..<Int(output.frameLength) {
                    energy += Double(samples[frame]) * Double(samples[frame])
                }
            }
        }
        let inputDuration = Double(batchCount * Int(framesPerBatch)) / sampleRate
        let outputDuration = Double(totalOutputFrames) / 16_000
        XCTAssertEqual(outputDuration, inputDuration, accuracy: 0.04,
            "Streaming conversion must retain duration across every tap, allowing resampler latency", file: file, line: line)
        XCTAssertEqual(laterNonemptyBatches, 10,
            "The converter must still produce samples at the end of the capture", file: file, line: line)
        let rms = sqrt(energy / Double(max(1, totalOutputFrames)))
        XCTAssertGreaterThan(rms, 0.1, "Resampled audio must contain the input signal", file: file, line: line)
        XCTAssertLessThan(rms, 0.3, file: file, line: line)
    }
}
