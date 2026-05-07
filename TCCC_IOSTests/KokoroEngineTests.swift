import Foundation
import XCTest
@testable import TCCC_IOS

final class KokoroEngineTests: XCTestCase {
    func testSynthesizerResultIsWrittenAsPlayableAudioWithSentenceTimings() async throws {
        let audioData = makeSilentWAV(duration: 0.6)
        let engine = KokoroEngine(nativeSynthesizer: StubNativeSynthesizer(audioData: audioData))

        let result = try await engine.synthesize(
            text: "Alpha bravo. Charlie delta.",
            voice: "af_heart",
            speed: 1.1,
            pitchSemitones: -0.5
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.audioURL.path))
        XCTAssertGreaterThan(result.duration, 0.5)
        XCTAssertEqual(result.sentenceTimings.count, 2)
        XCTAssertEqual(result.sentenceTimings[0].sentence, "Alpha bravo.")
        XCTAssertEqual(result.sentenceTimings[0].startTime, 0, accuracy: 0.01)
        XCTAssertEqual(result.sentenceTimings[1].sentence, "Charlie delta.")
        XCTAssertEqual(result.sentenceTimings[1].endTime, result.duration, accuracy: 0.05)
    }

    func testDefaultRendererProducesAudioFileWithoutModelDownload() async throws {
        let engine = KokoroEngine()

        let result = try await engine.synthesize(
            text: "TCCC sender audio check.",
            voice: "af_heart",
            speed: 1.0,
            pitchSemitones: 0
        )

        let audioData = try Data(contentsOf: result.audioURL)
        XCTAssertGreaterThan(audioData.count, 44)
        XCTAssertGreaterThan(result.duration, 0.1)
    }
}

private struct StubNativeSynthesizer: KokoroNativeSynthesizing {
    let audioData: Data

    func synthesize(_ request: KokoroNativeSynthesisRequest) async throws -> KokoroNativeSynthesisResult {
        KokoroNativeSynthesisResult(audioData: audioData)
    }
}

private func makeSilentWAV(duration: TimeInterval, sampleRate: Int = 24_000) -> Data {
    let sampleCount = max(1, Int(duration * Double(sampleRate)))
    let dataByteCount = sampleCount * MemoryLayout<Int16>.size
    var data = Data()

    data.append(contentsOf: "RIFF".utf8)
    data.append(UInt32(36 + dataByteCount).littleEndianData)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    data.append(UInt32(16).littleEndianData)
    data.append(UInt16(1).littleEndianData)
    data.append(UInt16(1).littleEndianData)
    data.append(UInt32(sampleRate).littleEndianData)
    data.append(UInt32(sampleRate * MemoryLayout<Int16>.size).littleEndianData)
    data.append(UInt16(MemoryLayout<Int16>.size).littleEndianData)
    data.append(UInt16(16).littleEndianData)
    data.append(contentsOf: "data".utf8)
    data.append(UInt32(dataByteCount).littleEndianData)
    data.append(Data(repeating: 0, count: dataByteCount))

    return data
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
