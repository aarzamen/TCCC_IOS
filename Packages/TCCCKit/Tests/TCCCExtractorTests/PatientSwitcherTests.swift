// PatientSwitcherTests
//
// Parity tests for `PatientSwitcher` against `_check_new_patient` from
// /Users/ama/TCCC_FEB_2026/src/state.py:530–567. Several assertions here are
// ported from
// /Users/ama/TCCC_FEB_2026/tests/test_state_negation.py:TestMultiPatientRouting.

import XCTest
@testable import TCCCExtractor

final class PatientSwitcherTests: XCTestCase {

    private let s = PatientSwitcher()

    // MARK: - PATIENT_2 cues (most common)

    func testCasualtyTwoSwitchesToP2() {
        XCTAssertEqual(s.detectSwitch(in: "Moving to casualty two now."), "PATIENT_2")
    }

    func testCasualtyDigitTwoSwitchesToP2() {
        XCTAssertEqual(s.detectSwitch(in: "Casualty 2 is bleeding heavily."), "PATIENT_2")
    }

    func testSecondCasualtySwitchesToP2() {
        XCTAssertEqual(s.detectSwitch(in: "Second casualty is further out."), "PATIENT_2")
    }

    func testPatientTwoSwitchesToP2() {
        XCTAssertEqual(s.detectSwitch(in: "Patient two is alert."), "PATIENT_2")
    }

    func testPatientDigitTwoSwitchesToP2() {
        XCTAssertEqual(s.detectSwitch(in: "Patient 2 has a chest wound."), "PATIENT_2")
    }

    func testAnotherPatientSwitchesToP2() {
        XCTAssertEqual(s.detectSwitch(in: "Another patient over here."), "PATIENT_2")
    }

    func testAnotherCasualtySwitchesToP2() {
        XCTAssertEqual(s.detectSwitch(in: "Another casualty needs help."), "PATIENT_2")
    }

    func testNextPatientSwitchesToP2() {
        XCTAssertEqual(s.detectSwitch(in: "Next patient please."), "PATIENT_2")
    }

    func testNextCasualtySwitchesToP2() {
        XCTAssertEqual(s.detectSwitch(in: "Next casualty is twenty meters out."), "PATIENT_2")
    }

    func testMovingToCasualtyBareSwitchesToP2() {
        // "moving to casualty" with no number defaults to P2.
        XCTAssertEqual(s.detectSwitch(in: "Moving to casualty now."), "PATIENT_2")
    }

    func testMovingToPatientBareSwitchesToP2() {
        XCTAssertEqual(s.detectSwitch(in: "Moving to patient now."), "PATIENT_2")
    }

    // MARK: - PATIENT_3 cues

    func testCasualtyThreeSwitchesToP3() {
        XCTAssertEqual(s.detectSwitch(in: "Casualty three is over there."), "PATIENT_3")
    }

    func testCasualtyDigitThreeSwitchesToP3() {
        XCTAssertEqual(s.detectSwitch(in: "Casualty 3 needs immediate attention."), "PATIENT_3")
    }

    func testThirdCasualtySwitchesToP3() {
        XCTAssertEqual(s.detectSwitch(in: "Third casualty is unconscious."), "PATIENT_3")
    }

    func testPatientThreeSwitchesToP3() {
        XCTAssertEqual(s.detectSwitch(in: "Patient three is here."), "PATIENT_3")
    }

    func testMovingToPatientThreeSwitchesToP3() {
        XCTAssertEqual(s.detectSwitch(in: "Moving to patient three."), "PATIENT_3")
    }

    func testMovingToCasualtyThreeSwitchesToP3() {
        XCTAssertEqual(s.detectSwitch(in: "Moving to casualty three."), "PATIENT_3")
    }

    // MARK: - PATIENT_1 cues

    func testCasualtyOneSwitchesToP1() {
        XCTAssertEqual(s.detectSwitch(in: "Back to casualty one."), "PATIENT_1")
    }

    func testCasualtyDigitOneSwitchesToP1() {
        XCTAssertEqual(s.detectSwitch(in: "Casualty 1 status update."), "PATIENT_1")
    }

    func testFirstCasualtySwitchesToP1() {
        XCTAssertEqual(s.detectSwitch(in: "First casualty is stable."), "PATIENT_1")
    }

    func testPatientOneSwitchesToP1() {
        XCTAssertEqual(s.detectSwitch(in: "Patient one is awake."), "PATIENT_1")
    }

    func testStartingWithCasualtyOneSwitchesToP1() {
        XCTAssertEqual(s.detectSwitch(in: "Starting with casualty one."), "PATIENT_1")
    }

    // MARK: - No switch

    func testNoSwitchOnPlainSentence() {
        XCTAssertNil(s.detectSwitch(in: "Airway is patent, breathing normal."))
    }

    func testNoSwitchOnBleedingMention() {
        XCTAssertNil(s.detectSwitch(in: "Significant bleeding from the right thigh."))
    }

    func testEmptyStringNoSwitch() {
        XCTAssertNil(s.detectSwitch(in: ""))
    }

    // MARK: - Priority order
    //
    // Python checks PATIENT_3 first, then PATIENT_2, then PATIENT_1. If the
    // same sentence mentions multiple patients, PATIENT_3 wins.

    func testPriorityP3WinsOverP2() {
        XCTAssertEqual(
            s.detectSwitch(in: "casualty three is worse than casualty two."),
            "PATIENT_3")
    }

    func testPriorityP3WinsOverP1() {
        XCTAssertEqual(
            s.detectSwitch(in: "casualty three is talking to casualty one."),
            "PATIENT_3")
    }

    func testPriorityP2WinsOverP1() {
        XCTAssertEqual(
            s.detectSwitch(in: "casualty two is bigger than casualty one."),
            "PATIENT_2")
    }

    // MARK: - Case insensitivity

    func testCaseInsensitiveLowercase() {
        XCTAssertEqual(s.detectSwitch(in: "casualty two"), "PATIENT_2")
    }

    func testCaseInsensitiveUppercase() {
        XCTAssertEqual(s.detectSwitch(in: "CASUALTY TWO"), "PATIENT_2")
    }

    func testCaseInsensitiveMixed() {
        XCTAssertEqual(s.detectSwitch(in: "Casualty Two"), "PATIENT_2")
    }
}
