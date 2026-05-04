import XCTest
@testable import TCCCDomain

final class MARCHStateTests: XCTestCase {

    // MARK: - Defaults

    func testDefaultsMatchPythonFrozenDataclass() {
        let m = MARCHState()
        XCTAssertFalse(m.hemorrhageIdentified)
        XCTAssertFalse(m.hemorrhageAssessed)
        XCTAssertNil(m.hemorrhageLocation)
        XCTAssertNil(m.hemorrhageIntervention)
        XCTAssertNil(m.hemorrhageEffective)
        XCTAssertNil(m.airwayStatus)
        XCTAssertNil(m.airwayIntervention)
        XCTAssertNil(m.respirationStatus)
        XCTAssertNil(m.respirationIntervention)
        XCTAssertNil(m.breathSounds)
        XCTAssertNil(m.pulseStatus)
        XCTAssertNil(m.skinSigns)
        XCTAssertNil(m.circulationIntervention)
        XCTAssertNil(m.consciousness)
        XCTAssertNil(m.pupilResponse)
        XCTAssertNil(m.hypothermiaPrevention)
    }

    // MARK: - get_phase_status: M (Massive Hemorrhage)

    func testPhaseStatusM_doneWhenInterventionPresent() {
        let m = MARCHState(hemorrhageIntervention: "tourniquet applied")
        XCTAssertEqual(m.getPhaseStatus(.massive), .done)
    }

    func testPhaseStatusM_doneWhenAssessedWithNoBleeding() {
        // Python: hemorrhage was checked and none found — still counts.
        let m = MARCHState(hemorrhageAssessed: true)
        XCTAssertEqual(m.getPhaseStatus(.massive), .done)
    }

    func testPhaseStatusM_inProgressWhenIdentifiedOnly() {
        let m = MARCHState(hemorrhageIdentified: true)
        XCTAssertEqual(m.getPhaseStatus(.massive), .inProgress)
    }

    func testPhaseStatusM_inProgressWhenLocationOnly() {
        let m = MARCHState(hemorrhageLocation: "right thigh")
        XCTAssertEqual(m.getPhaseStatus(.massive), .inProgress)
    }

    func testPhaseStatusM_notAssessedByDefault() {
        XCTAssertEqual(MARCHState().getPhaseStatus(.massive), .notAssessed)
    }

    // MARK: - get_phase_status: A (Airway)

    func testPhaseStatusA_doneWhenStatusPresent() {
        let m = MARCHState(airwayStatus: "patent")
        XCTAssertEqual(m.getPhaseStatus(.airway), .done)
    }

    func testPhaseStatusA_inProgressWhenInterventionWithoutStatus() {
        let m = MARCHState(airwayIntervention: "NPA inserted")
        XCTAssertEqual(m.getPhaseStatus(.airway), .inProgress)
    }

    func testPhaseStatusA_notAssessedByDefault() {
        XCTAssertEqual(MARCHState().getPhaseStatus(.airway), .notAssessed)
    }

    // MARK: - get_phase_status: R (Respiration)

    func testPhaseStatusR_doneWhenBreathSoundsOrStatus() {
        XCTAssertEqual(
            MARCHState(respirationStatus: "labored").getPhaseStatus(.respiration),
            .done
        )
        XCTAssertEqual(
            MARCHState(breathSounds: "diminished left").getPhaseStatus(.respiration),
            .done
        )
    }

    func testPhaseStatusR_inProgressWhenInterventionOnly() {
        let m = MARCHState(respirationIntervention: "Chest seal applied")
        XCTAssertEqual(m.getPhaseStatus(.respiration), .inProgress)
    }

    func testPhaseStatusR_notAssessedByDefault() {
        XCTAssertEqual(MARCHState().getPhaseStatus(.respiration), .notAssessed)
    }

    // MARK: - get_phase_status: C (Circulation)

    func testPhaseStatusC_doneWhenPulseOrSkinSigns() {
        XCTAssertEqual(
            MARCHState(pulseStatus: "weak radial").getPhaseStatus(.circulation),
            .done
        )
        XCTAssertEqual(
            MARCHState(skinSigns: "cool clammy").getPhaseStatus(.circulation),
            .done
        )
    }

    func testPhaseStatusC_inProgressWhenInterventionOnly() {
        let m = MARCHState(circulationIntervention: "IV access established")
        XCTAssertEqual(m.getPhaseStatus(.circulation), .inProgress)
    }

    func testPhaseStatusC_notAssessedByDefault() {
        XCTAssertEqual(MARCHState().getPhaseStatus(.circulation), .notAssessed)
    }

    // MARK: - get_phase_status: H (Head/Hypothermia)

    func testPhaseStatusH_doneWhenConsciousnessOrPupils() {
        XCTAssertEqual(
            MARCHState(consciousness: "Alert").getPhaseStatus(.head),
            .done
        )
        XCTAssertEqual(
            MARCHState(pupilResponse: "equal and reactive").getPhaseStatus(.head),
            .done
        )
    }

    func testPhaseStatusH_inProgressWhenHypothermiaOnly() {
        let m = MARCHState(hypothermiaPrevention: "hypothermia wrap applied")
        XCTAssertEqual(m.getPhaseStatus(.head), .inProgress)
    }

    func testPhaseStatusH_notAssessedByDefault() {
        XCTAssertEqual(MARCHState().getPhaseStatus(.head), .notAssessed)
    }

    // MARK: - Equality + Codable

    func testEqualityIsValueBased() {
        let a = MARCHState(
            hemorrhageIdentified: true,
            hemorrhageLocation: "left arm",
            airwayStatus: "patent",
            consciousness: "Alert"
        )
        let b = MARCHState(
            hemorrhageIdentified: true,
            hemorrhageLocation: "left arm",
            airwayStatus: "patent",
            consciousness: "Alert"
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testCodableRoundTrip() throws {
        let original = MARCHState(
            hemorrhageIdentified: true,
            hemorrhageAssessed: true,
            hemorrhageLocation: "right thigh",
            hemorrhageIntervention: "Tourniquet applied",
            hemorrhageEffective: true,
            airwayStatus: "patent",
            respirationStatus: "labored",
            breathSounds: "diminished left",
            pulseStatus: "weak radial",
            skinSigns: "cool clammy",
            consciousness: "Voice",
            pupilResponse: "equal and reactive",
            hypothermiaPrevention: "hypothermia wrap applied"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MARCHState.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
