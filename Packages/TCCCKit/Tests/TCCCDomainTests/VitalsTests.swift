import XCTest
@testable import TCCCDomain

final class VitalsTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultsAreAllNil() {
        let v = Vitals()
        XCTAssertNil(v.hr)
        XCTAssertNil(v.bp)
        XCTAssertNil(v.spo2)
        XCTAssertNil(v.rr)
        XCTAssertNil(v.gcs)
        XCTAssertNil(v.temperatureCelsius)
        XCTAssertNil(v.capillaryRefillSeconds)
    }

    // MARK: - In-range values

    func testInRangeValuesArePreserved() {
        let bp = BloodPressure(systolic: 120, diastolic: 80)
        let v = Vitals(
            hr: 80,
            bp: bp,
            spo2: 98,
            rr: 16,
            gcs: 15,
            temperatureCelsius: 37.0,
            capillaryRefillSeconds: 2.0
        )
        XCTAssertEqual(v.hr, 80)
        XCTAssertEqual(v.bp, bp)
        XCTAssertEqual(v.spo2, 98)
        XCTAssertEqual(v.rr, 16)
        XCTAssertEqual(v.gcs, 15)
        XCTAssertEqual(v.temperatureCelsius, 37.0)
        XCTAssertEqual(v.capillaryRefillSeconds, 2.0)
    }

    // MARK: - Range validation: HR (0–300)

    func testHrOutOfRangeBecomesNil() {
        XCTAssertNil(Vitals(hr: -1).hr)
        XCTAssertNil(Vitals(hr: 301).hr)
        XCTAssertNil(Vitals(hr: 9999).hr)
    }

    func testHrEdgeValuesArePreserved() {
        XCTAssertEqual(Vitals(hr: 0).hr, 0)
        XCTAssertEqual(Vitals(hr: 300).hr, 300)
    }

    // MARK: - Range validation: SpO2 (0–100)

    func testSpo2OutOfRangeBecomesNil() {
        XCTAssertNil(Vitals(spo2: -1).spo2)
        XCTAssertNil(Vitals(spo2: 101).spo2)
    }

    func testSpo2EdgeValuesArePreserved() {
        XCTAssertEqual(Vitals(spo2: 0).spo2, 0)
        XCTAssertEqual(Vitals(spo2: 100).spo2, 100)
    }

    // MARK: - Other fields

    func testRrOutOfRangeBecomesNil() {
        XCTAssertNil(Vitals(rr: -1).rr)
        XCTAssertNil(Vitals(rr: 999).rr)
    }

    func testGcsOutOfRangeBecomesNil() {
        // Valid GCS is 3–15.
        XCTAssertNil(Vitals(gcs: 2).gcs)
        XCTAssertNil(Vitals(gcs: 16).gcs)
        XCTAssertEqual(Vitals(gcs: 3).gcs, 3)
        XCTAssertEqual(Vitals(gcs: 15).gcs, 15)
    }

    func testTemperatureOutOfRangeBecomesNil() {
        XCTAssertNil(Vitals(temperatureCelsius: 19.0).temperatureCelsius)
        XCTAssertNil(Vitals(temperatureCelsius: 46.0).temperatureCelsius)
    }

    func testCapillaryRefillOutOfRangeBecomesNil() {
        XCTAssertNil(Vitals(capillaryRefillSeconds: -0.1).capillaryRefillSeconds)
        XCTAssertNil(Vitals(capillaryRefillSeconds: 21.0).capillaryRefillSeconds)
    }

    // MARK: - Non-throwing init

    func testInitDoesNotCrashOnAnyInput() {
        // Cover several wildly out-of-range combos at once.
        let v = Vitals(
            hr: -50,
            bp: BloodPressure(systolic: 200, diastolic: 100, palpated: true),
            spo2: 200,
            rr: -10,
            gcs: 999,
            temperatureCelsius: -100.0,
            capillaryRefillSeconds: -5.0
        )
        XCTAssertNil(v.hr)
        XCTAssertNotNil(v.bp) // BP is not range-validated by this struct
        XCTAssertNil(v.spo2)
        XCTAssertNil(v.rr)
        XCTAssertNil(v.gcs)
        XCTAssertNil(v.temperatureCelsius)
        XCTAssertNil(v.capillaryRefillSeconds)
    }

    // MARK: - BloodPressure

    func testBloodPressurePalpatedDefault() {
        let bp = BloodPressure(systolic: 120, diastolic: 80)
        XCTAssertFalse(bp.palpated)
    }

    func testBloodPressurePalpatedExplicit() {
        let bp = BloodPressure(systolic: 90, diastolic: 0, palpated: true)
        XCTAssertTrue(bp.palpated)
    }

    func testBloodPressureCodableRoundTrip() throws {
        let bp = BloodPressure(systolic: 110, diastolic: 70, palpated: false)
        let data = try JSONEncoder().encode(bp)
        let decoded = try JSONDecoder().decode(BloodPressure.self, from: data)
        XCTAssertEqual(decoded, bp)
    }

    // MARK: - Codable

    func testVitalsCodableRoundTrip() throws {
        let v = Vitals(
            hr: 110,
            bp: BloodPressure(systolic: 90, diastolic: 60, palpated: true),
            spo2: 92,
            rr: 24,
            gcs: 12,
            temperatureCelsius: 36.1,
            capillaryRefillSeconds: 3.5
        )
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(Vitals.self, from: data)
        XCTAssertEqual(decoded, v)
    }
}
