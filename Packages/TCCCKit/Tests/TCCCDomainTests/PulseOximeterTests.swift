import Foundation
import XCTest
@testable import TCCCDomain

final class PulseOximeterTests: XCTestCase {
    private let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)

    // Synthetic fixtures. Checksums were calculated independently of the Swift
    // decoder using the non-reflected 0x31 polynomial with bit reflection.
    private let numeric = Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x60, 0x3E, 0x00, 0x50, 0x00, 0xC0, 0x08])
    private let waveform = Data([0xAA, 0x55, 0x0F, 0x07, 0x02, 0x80, 0xFF, 0x45, 0xAA, 0x55, 0xE1])
    private let unknown = Data([0xAA, 0x55, 0x0F, 0x04, 0x4D, 0x12, 0x34, 0xD4])

    func testCRC8MaximMatchesStandardCheckVector() {
        XCTAssertEqual(LepuPulseOximeterDecoder.crc8Maxim(Array("123456789".utf8)), 0xA1)
    }

    func testNumericReadingPreservesEvidenceWithoutClaimingSignalQualityOrAcquisitionTime() throws {
        var decoder = LepuPulseOximeterDecoder()
        let reading = try singleReading(decoder.append(numeric, receivedAt: receivedAt))

        XCTAssertEqual(reading.spo2, 96)
        XCTAssertEqual(reading.pulseRate, 62)
        XCTAssertEqual(reading.perfusionIndex, 8.0)
        XCTAssertEqual(reading.rawFrame, numeric)
        XCTAssertEqual(reading.receivedAt, receivedAt)
        XCTAssertNil(reading.acquiredAt)
        XCTAssertEqual(reading.quality, .unknown)
        XCTAssertEqual(reading.protocolVersion, "lepu-s5w-observed-v1")
    }

    func testObservedLowByteLimitsAndPITenths() throws {
        let low = Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x01, 0x01, 0x00, 0x01, 0x00, 0xC0, 0xC7])
        let high = Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x64, 0xFF, 0x00, 0xFF, 0x00, 0xC0, 0x92])
        var decoder = LepuPulseOximeterDecoder()
        let minimum = try singleReading(decoder.append(low, receivedAt: receivedAt))
        let maximum = try singleReading(decoder.append(high, receivedAt: receivedAt))

        XCTAssertEqual(minimum.spo2, 1)
        XCTAssertEqual(minimum.pulseRate, 1)
        XCTAssertEqual(minimum.perfusionIndex, 0.1)
        XCTAssertEqual(maximum.spo2, 100)
        XCTAssertEqual(maximum.pulseRate, 255)
        XCTAssertEqual(maximum.perfusionIndex, 25.5)
        XCTAssertEqual(minimum.quality, .unknown)
        XCTAssertEqual(maximum.quality, .unknown)
    }

    func testZeroAndOutOfRangeSaturationRemainUnavailableWithoutErasingOtherEvidence() throws {
        let frames = [
            Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x00, 0x46, 0x00, 0x50, 0x00, 0xC0, 0x98]),
            Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x65, 0x46, 0x00, 0x50, 0x00, 0xC0, 0xB0]),
        ]
        var decoder = LepuPulseOximeterDecoder()
        for frame in frames {
            let reading = try singleReading(decoder.append(frame, receivedAt: receivedAt))
            XCTAssertNil(reading.spo2)
            XCTAssertEqual(reading.pulseRate, 70)
            XCTAssertEqual(reading.perfusionIndex, 8.0)
            XCTAssertEqual(reading.quality, .unavailable)
            XCTAssertEqual(reading.rawFrame, frame)
        }
    }

    func testZeroPulseDoesNotBecomeAClinicalZero() throws {
        let frame = Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x62, 0x00, 0x00, 0x50, 0x00, 0xC0, 0x40])
        var decoder = LepuPulseOximeterDecoder()
        let reading = try singleReading(decoder.append(frame, receivedAt: receivedAt))
        XCTAssertEqual(reading.spo2, 98)
        XCTAssertNil(reading.pulseRate)
        XCTAssertEqual(reading.quality, .unavailable)
    }

    func testAllZeroMeasurementFieldsAreNil() throws {
        let frame = Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0xC0, 0x96])
        var decoder = LepuPulseOximeterDecoder()
        let reading = try singleReading(decoder.append(frame, receivedAt: receivedAt))
        XCTAssertNil(reading.spo2)
        XCTAssertNil(reading.pulseRate)
        XCTAssertNil(reading.perfusionIndex)
        XCTAssertEqual(reading.quality, .unavailable)
    }

    func testZeroPIDoesNotInventPerfusionOrInvalidatePresentPulseAndSaturation() throws {
        let frame = Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x62, 0x46, 0x00, 0x00, 0x00, 0xC0, 0x4E])
        var decoder = LepuPulseOximeterDecoder()
        let reading = try singleReading(decoder.append(frame, receivedAt: receivedAt))
        XCTAssertEqual(reading.spo2, 98)
        XCTAssertEqual(reading.pulseRate, 70)
        XCTAssertNil(reading.perfusionIndex)
        XCTAssertEqual(reading.quality, .unknown)
    }

    func testUnverifiedPulseExtensionSuppressesAllNumericValues() throws {
        let frame = Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x62, 0x46, 0x01, 0x50, 0x00, 0xC0, 0xBA])
        var decoder = LepuPulseOximeterDecoder()
        let reading = try singleReading(decoder.append(frame, receivedAt: receivedAt))
        XCTAssertNil(reading.spo2)
        XCTAssertNil(reading.pulseRate)
        XCTAssertNil(reading.perfusionIndex)
        XCTAssertEqual(reading.quality, .unsupportedEncoding)
        XCTAssertEqual(reading.rawFrame, frame)
    }

    func testUnverifiedStatusBitsDoNotBecomeSignalQualityClaims() throws {
        let frame = Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x61, 0x49, 0x00, 0x15, 0xFF, 0xFF, 0x79])
        var decoder = LepuPulseOximeterDecoder()
        let reading = try singleReading(decoder.append(frame, receivedAt: receivedAt))
        XCTAssertEqual(reading.spo2, 97)
        XCTAssertEqual(reading.pulseRate, 73)
        XCTAssertEqual(reading.quality, .unknown)
        XCTAssertEqual(reading.rawFrame, frame)
    }

    func testWaveformMasksAmplitudeFlagAndPreservesOriginalBytes() throws {
        var decoder = LepuPulseOximeterDecoder()
        let packets = decoder.append(waveform, receivedAt: receivedAt)
        XCTAssertEqual(packets.count, 1)
        guard case .waveform(let wave) = try XCTUnwrap(packets.first) else {
            return XCTFail("Expected waveform")
        }
        XCTAssertEqual(wave.samples, [0, 127, 69, 42, 85])
        XCTAssertEqual(wave.rawFrame, waveform)
        XCTAssertEqual(wave.receivedAt, receivedAt)
    }

    func testEveryFragmentSplitWaitsForCompleteFrameAndUsesCompletingReceiptTime() throws {
        for split in 1..<numeric.count {
            var decoder = LepuPulseOximeterDecoder()
            XCTAssertTrue(decoder.append(numeric.prefix(split), receivedAt: receivedAt).isEmpty)
            let later = receivedAt.addingTimeInterval(1)
            let reading = try singleReading(decoder.append(numeric.suffix(numeric.count - split), receivedAt: later))
            XCTAssertEqual(reading.spo2, 96)
            XCTAssertEqual(reading.receivedAt, later)
            XCTAssertEqual(reading.rawFrame, numeric)
        }
    }

    func testByteAtATimeAndConcatenatedNotificationsPreservePacketOrder() throws {
        var decoder = LepuPulseOximeterDecoder()
        var packets: [PulseOximeterPacket] = []
        for byte in numeric {
            packets += decoder.append(Data([byte]), receivedAt: receivedAt)
        }
        XCTAssertEqual(try singleReading(packets).pulseRate, 62)
        let batch = decoder.append(waveform + unknown + numeric, receivedAt: receivedAt)
        XCTAssertEqual(batch.count, 3)
        guard batch.count == 3 else { return }
        guard case .waveform = batch[0], case .unknown = batch[1], case .reading = batch[2] else {
            return XCTFail("Notification order must be preserved")
        }
    }

    func testUnknownTypesRemainRawEvidence() throws {
        var decoder = LepuPulseOximeterDecoder()
        let packets = decoder.append(unknown, receivedAt: receivedAt)
        XCTAssertEqual(packets.count, 1)
        guard case .unknown(let raw, let timestamp) = try XCTUnwrap(packets.first) else {
            return XCTFail("Expected unknown raw evidence")
        }
        XCTAssertEqual(raw, unknown)
        XCTAssertEqual(timestamp, receivedAt)
    }

    func testIncompleteUnknownFrameDoesNotEmitItsPayloadAsANumericFrame() throws {
        let frame = Data([0xAA, 0x55, 0x0F, 0x0E, 0x4D]) + numeric + Data([0x4A])
        var decoder = LepuPulseOximeterDecoder()
        XCTAssertTrue(decoder.append(frame.dropLast(), receivedAt: receivedAt).isEmpty)
        let packets = decoder.append(frame.suffix(1), receivedAt: receivedAt.addingTimeInterval(1))
        XCTAssertEqual(packets.count, 1)
        guard case .unknown(let raw, _) = try XCTUnwrap(packets.first) else {
            return XCTFail("An embedded frame is payload, not a separate observation")
        }
        XCTAssertEqual(raw, frame)
    }

    func testCorruptUnknownLengthRecoversWithinLengthBoundWithOriginalReceiptTime() throws {
        var decoder = LepuPulseOximeterDecoder()
        // The unknown header claims the maximum length. The candidate is invalid
        // once 259 bytes arrive; its embedded numeric frame must then recover.
        let prefix = Data([0xAA, 0x55, 0x0F, 0xFF, 0x4D]) + numeric
        XCTAssertTrue(decoder.append(prefix, receivedAt: receivedAt).isEmpty)
        let packets = decoder.append(Data(repeating: 0, count: 242), receivedAt: receivedAt.addingTimeInterval(2))
        let reading = try singleReading(packets)
        XCTAssertEqual(reading.rawFrame, numeric)
        XCTAssertEqual(reading.receivedAt, receivedAt)
    }

    func testNoiseAndOverlappingSyncRecoverWithoutFalseReadings() throws {
        var decoder = LepuPulseOximeterDecoder()
        XCTAssertTrue(decoder.append(Data([0x00, 0x55, 0xAA, 0xAA]), receivedAt: receivedAt).isEmpty)
        let reading = try singleReading(decoder.append(numeric, receivedAt: receivedAt))
        XCTAssertEqual(reading.rawFrame, numeric)
    }

    func testChecksumCorruptionIsRejectedAndFollowingFrameRecovers() throws {
        var corrupt = numeric
        corrupt[5] ^= 1
        var decoder = LepuPulseOximeterDecoder()
        XCTAssertTrue(decoder.append(corrupt, receivedAt: receivedAt).isEmpty)
        XCTAssertEqual(try singleReading(decoder.append(numeric, receivedAt: receivedAt)).spo2, 96)
    }

    func testIncorrectPublicChecksumIsNotAcceptedAsAPlausibleReading() {
        let frame = Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x60, 0x3E, 0x00, 0x50, 0x00, 0xC0, 0xB9])
        var decoder = LepuPulseOximeterDecoder()
        XCTAssertTrue(decoder.append(frame, receivedAt: receivedAt).isEmpty)
    }

    func testCorruptKnownFrameLengthsDoNotBlockFollowingValidFrame() throws {
        for length: UInt8 in [0, 1, 2, 7, 9, 255] {
            var corrupted = numeric
            corrupted[3] = length
            var decoder = LepuPulseOximeterDecoder()
            let reading = try singleReading(decoder.append(corrupted + numeric, receivedAt: receivedAt))
            XCTAssertEqual(reading.rawFrame, numeric)
        }
    }

    func testResetDiscardsPartialFrameAcrossConnections() throws {
        var decoder = LepuPulseOximeterDecoder()
        XCTAssertTrue(decoder.append(numeric.prefix(6), receivedAt: receivedAt).isEmpty)
        decoder.reset()
        XCTAssertTrue(decoder.append(numeric.suffix(6), receivedAt: receivedAt).isEmpty)
        XCTAssertEqual(try singleReading(decoder.append(numeric, receivedAt: receivedAt)).spo2, 96)
    }

    func testLongNoiseStreamDoesNotPreventSubsequentRecovery() throws {
        var decoder = LepuPulseOximeterDecoder()
        XCTAssertTrue(decoder.append(Data(repeating: 0xAA, count: 100_000), receivedAt: receivedAt).isEmpty)
        XCTAssertEqual(try singleReading(decoder.append(numeric, receivedAt: receivedAt)).spo2, 96)
    }

    func testReadingAndWaveformRoundTripRetainSourceEvidenceAndIdentity() throws {
        var decoder = LepuPulseOximeterDecoder()
        let reading = try singleReading(decoder.append(numeric, receivedAt: receivedAt))
        let second = try singleReading(decoder.append(numeric, receivedAt: receivedAt))
        XCTAssertNotEqual(reading.id, second.id)
        XCTAssertEqual(try JSONDecoder().decode(PulseOximeterReading.self, from: JSONEncoder().encode(reading)), reading)
        let wave = PulseOximeterWaveform(receivedAt: receivedAt, rawFrame: waveform, samples: [0, 127, 69, 42, 85])
        XCTAssertEqual(try JSONDecoder().decode(PulseOximeterWaveform.self, from: JSONEncoder().encode(wave)), wave)
    }

    private func singleReading(
        _ packets: [PulseOximeterPacket],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> PulseOximeterReading {
        XCTAssertEqual(packets.count, 1, file: file, line: line)
        let first = try XCTUnwrap(packets.first, file: file, line: line)
        guard case .reading(let reading) = first else {
            XCTFail("Expected one reading", file: file, line: line)
            throw NSError(domain: "PulseOximeterTests", code: 1)
        }
        return reading
    }
}
