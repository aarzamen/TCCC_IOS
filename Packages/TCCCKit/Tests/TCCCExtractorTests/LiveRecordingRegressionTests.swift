// LiveRecordingRegressionTests
//
// Apple Speech segments from an improvised iPhone 17 Pro recording
// (2026-10-27), verbatim including recognition errors, minus the identity
// sentence. Each assertion is a fact the medic said that the first on-device
// DD 1380 export left off the card.

import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class LiveRecordingRegressionTests: XCTestCase {

    private let segments = [
        "This is test. I think it's working. It looks like we are 14. The patient is a actor duty male Gunshot went to the lower extremity he has learned oriented He has learned oriented times for applying tourniquet To the left lower extremity above the knee",
        "All right, but you wouldn't get you out of here All right going in for cover I'm gonna go ahead and get a set of vitals Heart rate is 99 bpm. His blood pressure is 120/60.",
        "Is it true rate 16 his SPO2 is 96% he's he's screaming pain. He's an eight out of 10 pain. I'm gonna go ahead and give him a combat pill pack so I'm gonna give him her pen For the antibiotic and then I'm gonna give him Mobic for the painkiller and probably ketamine as well Established IV access in the right AC I'm doing a blood sweep. I don't see any massive hemorrhage anywhere his airways clear.",
        "His breathing, no rain rhythm I hear rise and chest false respirations are normal",
        "I'm taking his temperature 38°F. I'm gonna go and wrap them up this space blanket. I'm gonna go and splint his right extremity. I've tried to give him I gave him antibiotics. I gave him a pen him. Mostly given TXA And I gave them Mobic for pain. I'll give him ketamine as well for pain.",
    ]

    private func patient() async throws -> PatientState {
        let engine = PatientStateEngine.standard()
        var t = Date(timeIntervalSince1970: 1_793_169_147)
        for segment in segments {
            await engine.processTranscript(segment, timestamp: t)
            t += 60
        }
        let snapshot = await engine.snapshot(of: "PATIENT_1")
        return try XCTUnwrap(snapshot)
    }

    func testTourniquetLocationIsTheLeftLowerExtremity() async throws {
        let p = try await patient()
        XCTAssertEqual(p.march.hemorrhageLocation, "left lower extremity")
        XCTAssertEqual(p.march.hemorrhageIntervention, "Tourniquet applied (left lower extremity)")
    }

    func testPainScoreIsEight() async throws {
        let p = try await patient()
        XCTAssertEqual(p.vitals.painScore, 8)
    }

    func testAirwayIsPatent() async throws {
        let p = try await patient()
        XCTAssertEqual(p.march.airwayStatus, "patent")
    }

    func testIVAccessIsRecorded() async throws {
        let p = try await patient()
        XCTAssertTrue(p.interventions.contains { $0.kind == .ivAccess })
    }

    // MARK: - Leftovers from the first on-device export (f-6055bd90)

    func testRespiratoryRateSurvivesTheMisheardLabel() async throws {
        // "Is it true rate 16" is Apple Speech for "respiratory rate 16".
        let p = try await patient()
        XCTAssertEqual(p.vitals.rr, 16)
    }

    func testErtapenemSurvivesTheMisheardName() async throws {
        // "her pen" and "a pen him" are Apple Speech for ertapenem.
        let p = try await patient()
        XCTAssertEqual(p.paws.antibiotics, "Ertapenem administered")
        XCTAssertEqual(p.interventions.filter { $0.kind == .antibiotic }.map(\.description),
                       ["Ertapenem administered"])
    }

    func testNamedPainMedicationsAreEachRecorded() async throws {
        // The kit stays the first-match descriptor; Mobic and ketamine, said in
        // the same breath, are their own rows, recorded once each.
        let p = try await patient()
        XCTAssertEqual(p.paws.pain, "Combat pill pack administered")
        XCTAssertEqual(p.interventions.filter { $0.kind == .painManagement }.map(\.description),
                       ["Combat pill pack administered", "Meloxicam administered", "Ketamine administered"])
    }

    func testFactsAlreadyCapturedStayCaptured() async throws {
        let p = try await patient()
        XCTAssertEqual(p.vitals.hr, 99)
        XCTAssertEqual(p.vitals.bp, BloodPressure(systolic: 120, diastolic: 60, palpated: false))
        XCTAssertEqual(p.vitals.spo2, 96)
        let kinds = Set(p.interventions.map(\.kind))
        for kind: InterventionKind in [.tourniquet, .painManagement, .antibiotic, .medication,
                                       .splint, .hypothermiaPrevention] {
            XCTAssertTrue(kinds.contains(kind), "\(kind) missing")
        }
    }
}
