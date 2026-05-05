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

    // MARK: - allPhasesAssessed (PAWS gating, 2026 sprint 2.1)

    func testAllPhasesAssessedFalseByDefault() {
        XCTAssertFalse(MARCHState().allPhasesAssessed)
    }

    func testAllPhasesAssessedFalseWhenSomePhasesUnassessed() {
        // M done + A done, but R/C/H not assessed
        let m = MARCHState(
            hemorrhageAssessed: true,
            airwayStatus: "patent"
        )
        XCTAssertFalse(m.allPhasesAssessed)
    }

    func testAllPhasesAssessedTrueWhenAllPhasesHaveStatus() {
        let m = MARCHState(
            hemorrhageAssessed: true,
            airwayStatus: "patent",
            respirationStatus: "normal",
            pulseStatus: "strong radial",
            consciousness: "Alert"
        )
        XCTAssertTrue(m.allPhasesAssessed)
    }

    func testAllPhasesAssessedTrueWithMixOfDoneAndInProgress() {
        // Five phases, each at least .inProgress: hemorrhageIdentified
        // (in-progress), airwayIntervention (in-progress),
        // respirationIntervention (in-progress), circulationIntervention
        // (in-progress), hypothermiaPrevention (in-progress for head).
        let m = MARCHState(
            hemorrhageIdentified: true,
            airwayIntervention: "NPA inserted",
            respirationIntervention: "chest seal",
            circulationIntervention: "IV access",
            hypothermiaPrevention: "wrap"
        )
        XCTAssertTrue(m.allPhasesAssessed)
    }

    // MARK: - Hypothermia / TBI sub-phase status (2026 split, sprint 2.2)

    func testHypothermiaPhaseStatusNotAssessedByDefault() {
        XCTAssertEqual(MARCHState().hypothermiaPhaseStatus, .notAssessed)
    }

    func testHypothermiaPhaseStatusDoneWhenWrapApplied() {
        let m = MARCHState(hypothermiaPrevention: "Hypothermia wrap applied")
        XCTAssertEqual(m.hypothermiaPhaseStatus, .done)
    }

    func testTbiPhaseStatusNotAssessedByDefault() {
        XCTAssertEqual(MARCHState().tbiPhaseStatus, .notAssessed)
    }

    func testTbiPhaseStatusDoneWhenConsciousnessSet() {
        let m = MARCHState(consciousness: "Alert")
        XCTAssertEqual(m.tbiPhaseStatus, .done)
    }

    func testTbiPhaseStatusDoneWhenPupilsSet() {
        let m = MARCHState(pupilResponse: "equal")
        XCTAssertEqual(m.tbiPhaseStatus, .done)
    }

    func testHypothermiaAndTbiAreIndependent() {
        // Wrap applied — hypothermia .done, TBI still .notAssessed.
        let hypoOnly = MARCHState(hypothermiaPrevention: "wrap")
        XCTAssertEqual(hypoOnly.hypothermiaPhaseStatus, .done)
        XCTAssertEqual(hypoOnly.tbiPhaseStatus, .notAssessed)

        // AVPU recorded — TBI .done, hypothermia still .notAssessed.
        let tbiOnly = MARCHState(consciousness: "Alert")
        XCTAssertEqual(tbiOnly.hypothermiaPhaseStatus, .notAssessed)
        XCTAssertEqual(tbiOnly.tbiPhaseStatus, .done)
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
