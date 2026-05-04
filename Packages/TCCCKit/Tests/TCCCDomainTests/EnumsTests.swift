import XCTest
@testable import TCCCDomain

final class EnumsTests: XCTestCase {

    // Raw values must match the strings used in the Python prototype
    // (state.py:266–301 for MARCH phase letters, lines 451–456 for
    // classifications, line 391/669 for airway, lines 429–432 for AVPU,
    // line 270 for the "✓"/"·"/"-" glyphs).

    func testMarchPhaseRawValues() {
        XCTAssertEqual(MarchPhase.massive.rawValue, "M")
        XCTAssertEqual(MarchPhase.airway.rawValue, "A")
        XCTAssertEqual(MarchPhase.respiration.rawValue, "R")
        XCTAssertEqual(MarchPhase.circulation.rawValue, "C")
        XCTAssertEqual(MarchPhase.head.rawValue, "H")
    }

    func testPhaseStatusGlyphs() {
        XCTAssertEqual(PhaseStatus.done.rawValue, "✓")
        XCTAssertEqual(PhaseStatus.inProgress.rawValue, "·")
        XCTAssertEqual(PhaseStatus.notAssessed.rawValue, "-")
    }

    func testClassificationRawValues() {
        XCTAssertEqual(Classification.urgent.rawValue, "Urgent")
        XCTAssertEqual(Classification.urgentSurgical.rawValue, "Urgent Surgical")
        XCTAssertEqual(Classification.priority.rawValue, "Priority")
        XCTAssertEqual(Classification.routine.rawValue, "Routine")
        XCTAssertEqual(Classification.expectant.rawValue, "Expectant")
    }

    func testAirwayStatusRawValues() {
        XCTAssertEqual(AirwayStatus.patent.rawValue, "patent")
        XCTAssertEqual(AirwayStatus.compromised.rawValue, "compromised")
        XCTAssertEqual(AirwayStatus.obstructed.rawValue, "obstructed")
    }

    func testConsciousnessLevelRawValues() {
        XCTAssertEqual(ConsciousnessLevel.alert.rawValue, "Alert")
        XCTAssertEqual(ConsciousnessLevel.voice.rawValue, "Voice")
        XCTAssertEqual(ConsciousnessLevel.pain.rawValue, "Pain")
        XCTAssertEqual(ConsciousnessLevel.unresponsive.rawValue, "Unresponsive")
    }

    func testAllEnumsRoundTripCodable() throws {
        try roundTrip(MarchPhase.airway)
        try roundTrip(PhaseStatus.inProgress)
        try roundTrip(Classification.urgentSurgical)
        try roundTrip(AirwayStatus.compromised)
        try roundTrip(ConsciousnessLevel.unresponsive)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws {
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: data)
        XCTAssertEqual(decoded, value)
    }
}
