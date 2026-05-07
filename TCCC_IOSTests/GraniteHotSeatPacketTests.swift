import XCTest
@testable import TCCC_IOS

@MainActor
final class GraniteHotSeatPacketTests: XCTestCase {
    func testPacketContainsSegmentsAndBlockedActions() {
        var ledger = TranscriptSegmentLedger()
        ledger.appendRaw(
            text: "tourniquet applied left thigh",
            startMs: 0,
            endMs: 1200,
            backend: .appleSpeech,
            isFinal: true
        )

        let packet = HotSeatPacketBuilder.build(
            activePatientId: "PATIENT_1",
            segments: ledger.normalizedSegments,
            deterministicFacts: [],
            date: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(packet.activePatientId, "PATIENT_1")
        XCTAssertEqual(packet.segments.count, 1)
        XCTAssertTrue(packet.blockedActions.contains(.mutatePatientState))
        XCTAssertTrue(packet.blockedActions.contains(.inventLocation))
        XCTAssertTrue(packet.blockedActions.contains(.downloadModelWeights))
    }

    func testPacketDerivesKnownPatientsFromActivePatientAndFacts() {
        let fact = DeterministicFact(
            id: "det-1",
            patientId: "PATIENT_2",
            domain: "march",
            field: "hemorrhageIntervention",
            value: "tourniquet",
            evidenceIds: ["seg-1"],
            extractor: "HemorrhageExtractor",
            confidence: .high
        )

        let packet = HotSeatPacketBuilder.build(
            activePatientId: "PATIENT_1",
            segments: [],
            deterministicFacts: [fact],
            date: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(packet.knownPatientIds, ["PATIENT_1", "PATIENT_2"])
        XCTAssertEqual(packet.allowedSchemas, [.transcriptSalvagePatch, .graniteCandidatePatch])
    }

    func testPacketJSONDoesNotContainUnboundedPromptField() throws {
        let packet = HotSeatPacketBuilder.build(
            activePatientId: "PATIENT_1",
            segments: [],
            deterministicFacts: [],
            date: Date(timeIntervalSince1970: 0)
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(packet), as: UTF8.self)

        XCTAssertFalse(json.contains("\"prompt\""))
        XCTAssertFalse(json.contains("\"rawPrompt\""))
        XCTAssertFalse(json.contains("\"instructions\""))
    }
}
