import XCTest
@testable import TCCCDomain

final class TourniquetDeviceTests: XCTestCase {

    func testNamedLimbDevices() {
        let cases: [(String, String)] = [
            ("Applying a tourniquet now, CAT tourniquet,", "CAT"),
            ("cat tonic high and tight on the left leg", "CAT"),
            ("combat application tourniquet to the right arm", "CAT"),
            ("SOFT-T wide applied left arm", "SOFTT-W"),
            ("softt applied", "SOFTT-W"),
            ("SAM XT on the right thigh", "SAM XT"),
            ("TMT applied", "TMT"),
            ("tactical mechanical tourniquet", "TMT"),
            ("RMT on the arm", "RMT"),
            ("EMT tourniquet inflated", "EMT"),
        ]
        for (text, name) in cases {
            let device = TourniquetDevice.named(in: text)
            XCTAssertEqual(device?.name, name, text)
            XCTAssertEqual(device?.isJunctional, false, text)
        }
    }

    func testNamedJunctionalDevices() {
        let cases: [(String, String)] = [
            ("SAM junctional tourniquet to the left groin", "SAM-JT"),
            ("SJT applied", "SAM-JT"),
            ("JETT applied", "JETT"),
            ("CRoC applied to the groin", "CRoC"),
            ("AAJT applied", "AAJT"),
        ]
        for (text, name) in cases {
            let device = TourniquetDevice.named(in: text)
            XCTAssertEqual(device?.name, name, text)
            XCTAssertEqual(device?.isJunctional, true, text)
        }
    }

    func testUnnamedOrLookalikeTextGivesNothing() {
        for text in ["Tourniquet applied", "tourniquet high and tight", "CAT scan negative",
                     "soft tissue injury, tourniquet applied", "the EMT applied a tourniquet",
                     "location indicated", "Same extremity"] {
            XCTAssertNil(TourniquetDevice.named(in: text), text)
        }
    }

    func testDescriptionRoundTrip() {
        XCTAssertEqual(TourniquetDevice.appliedDescription(device: nil), "Tourniquet applied")
        let cat = TourniquetDevice.named(in: "CAT tourniquet")
        XCTAssertEqual(TourniquetDevice.appliedDescription(device: cat), "Tourniquet applied (CAT)")
        XCTAssertEqual(TourniquetDevice.named(in: "Tourniquet applied (CAT)")?.name, "CAT")
    }
}
