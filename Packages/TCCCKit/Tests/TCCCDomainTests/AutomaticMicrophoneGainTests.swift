import XCTest
import TCCCDomain

final class AutomaticMicrophoneGainTests: XCTestCase {
    func testFallbackRaisesQuietSpeechGraduallyWithoutExceedingBoostLimit() {
        var gain = AutomaticMicrophoneGain(mode: .softwareAutomatic)
        let first = gain.gain(rms: 0.02, peak: 0.04, duration: 0.02)
        XCTAssertGreaterThan(first, 1)
        XCTAssertLessThan(first, 1.2)
        var final: Float = 0
        for _ in 0..<300 { final = gain.gain(rms: 0.02, peak: 0.04, duration: 0.02) }
        XCTAssertGreaterThan(final, 3.8)
        XCTAssertLessThanOrEqual(final, 4)
    }

    func testSuddenLoudInputHasHeadroomImmediately() {
        var gain = AutomaticMicrophoneGain(mode: .softwareAutomatic)
        for _ in 0..<300 { _ = gain.gain(rms: 0.02, peak: 0.04, duration: 0.02) }
        let reduced = gain.gain(rms: 0.7, peak: 1.2, duration: 0.02)
        XCTAssertLessThanOrEqual(reduced * 1.2, 0.891)
        XCTAssertLessThan(reduced, 1)
    }

    func testSilenceAndBackgroundNoiseDoNotBuildGain() {
        var gain = AutomaticMicrophoneGain(mode: .softwareAutomatic)
        for _ in 0..<500 {
            XCTAssertEqual(gain.gain(rms: 0.0005, peak: 0.001, duration: 0.02), 1)
        }
        for _ in 0..<300 { _ = gain.gain(rms: 0.02, peak: 0.04, duration: 0.02) }
        XCTAssertLessThanOrEqual(gain.gain(rms: 0, peak: 0, duration: 0.02), 1)
    }

    func testSystemAGCIsNotBoostedAgainButStillHasPeakProtection() {
        var gain = AutomaticMicrophoneGain(mode: .systemAutomatic)
        for _ in 0..<500 {
            XCTAssertEqual(gain.gain(rms: 0.02, peak: 0.04, duration: 0.02), 1)
        }
        XCTAssertLessThanOrEqual(gain.gain(rms: 0.9, peak: 1.8, duration: 0.02) * 1.8, 0.891)
    }

    func testNonfiniteOrInvalidMeasurementsCannotCreateNonfiniteGain() {
        for mode in [MicrophoneGainMode.systemAutomatic, .softwareAutomatic] {
            var gain = AutomaticMicrophoneGain(mode: mode)
            for values: (Float, Float, Double) in [(.nan, 1, 0.02), (1, .infinity, 0.02),
                                                   (-1, -2, 0.02), (0.1, 0.2, .nan), (0.1, 0.2, -1)] {
                let value = gain.gain(rms: values.0, peak: values.1, duration: values.2)
                XCTAssertTrue(value.isFinite)
                XCTAssertGreaterThanOrEqual(value, 0)
                XCTAssertTrue(gain.gainDb.isFinite)
            }
        }
    }
}
