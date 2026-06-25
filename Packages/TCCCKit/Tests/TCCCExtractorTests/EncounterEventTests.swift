// Packages/TCCCKit/Tests/TCCCExtractorTests/EncounterEventTests.swift
import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class EncounterEventTests: XCTestCase {

    private func roundTrip(_ event: EncounterEvent) throws -> EncounterEvent {
        let data = try JSONEncoder().encode(event)
        return try JSONDecoder().decode(EncounterEvent.self, from: data)
    }

    func testASRSegmentRoundTripsAndExposesIdentity() throws {
        let event = EncounterEvent.asrSegment(.init(
            id: "seg-1", patientId: "PATIENT_1", timestampUnix: 1000,
            text: "GSW right thigh", backend: "appleSpeech", isFinal: true))
        XCTAssertEqual(try roundTrip(event), event)
        XCTAssertEqual(event.id, "seg-1")
        XCTAssertEqual(event.patientId, "PATIENT_1")
        XCTAssertEqual(event.timestampUnix, 1000)
    }

    func testDeterministicFactCarriesDeltaAndEvidence() throws {
        let event = EncounterEvent.deterministicFact(.init(
            id: "fact-1", patientId: "PATIENT_1", timestampUnix: 1000,
            delta: .vitalsHR(110), evidenceIds: ["seg-1"], extractor: "VitalsExtractor"))
        XCTAssertEqual(try roundTrip(event), event)
        if case .deterministicFact(let p) = event { XCTAssertEqual(p.delta, .vitalsHR(110)) }
        else { XCTFail("wrong case") }
    }

    func testOperatorAcceptedAndRejectedRoundTrip() throws {
        let accepted = EncounterEvent.operatorAcceptedFact(.init(
            id: "op-1", patientId: "PATIENT_1", timestampUnix: 1000,
            write: .heartRate(110), sourceFactId: "g-1",
            domain: "vitals", field: "heartRate", rawValue: "110"))
        let rejected = EncounterEvent.operatorRejectedFact(.init(
            id: "op-2", patientId: "PATIENT_1", timestampUnix: 1001,
            write: nil, sourceFactId: "g-2",
            domain: "vitals", field: "heartRate", rawValue: "200"))
        XCTAssertEqual(try roundTrip(accepted), accepted)
        XCTAssertEqual(try roundTrip(rejected), rejected)
    }

    func testLifecycleRoundTrips() throws {
        let event = EncounterEvent.lifecycle(.init(
            id: "lc-1", patientId: "PATIENT_1", timestampUnix: 1000, kind: .encounterStarted))
        XCTAssertEqual(try roundTrip(event), event)
    }

    func testEncounterLogAppendsAndIsImmutableFromOutside() throws {
        var log = EncounterLog()
        XCTAssertTrue(log.events.isEmpty)
        log.append(.lifecycle(.init(id: "lc-1", patientId: "PATIENT_1", timestampUnix: 1, kind: .encounterStarted)))
        log.append(.asrSegment(.init(id: "seg-1", patientId: "PATIENT_1", timestampUnix: 2, text: "x", backend: "demo", isFinal: true)))
        XCTAssertEqual(log.events.count, 2)
        XCTAssertEqual(log.events.first?.id, "lc-1")
        // events has no public setter — this line must not compile if uncommented:
        // log.events = []
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(try JSONDecoder().decode(EncounterLog.self, from: data), log)
    }

    func testDeltaCodableRoundTripForRepresentativeCases() throws {
        let deltas: [PatientStateDelta] = [
            .mechanismOfInjury("GSW"), .marchPhase(.massive), .classification(.urgent),
            .appendInjury("femur fracture"), .setInjuries(["a", "b"]),
            .vitalsBP(BloodPressure(systolic: 90, diastolic: 60, palpated: false)),
            .hemorrhageIntervention("tourniquet applied"), .pawsPain("ketamine"),
            .appendIntervention(Intervention(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                timestamp: Date(timeIntervalSince1970: 5), kind: .tourniquet, description: "TQ")),
        ]
        for d in deltas {
            let data = try JSONEncoder().encode(d)
            XCTAssertEqual(try JSONDecoder().decode(PatientStateDelta.self, from: data), d)
        }
    }
}
