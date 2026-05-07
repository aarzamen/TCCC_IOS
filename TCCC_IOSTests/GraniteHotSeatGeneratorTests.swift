import XCTest
@testable import TCCC_IOS

final class GraniteHotSeatGeneratorTests: XCTestCase {
    func testStructuredBackendReturnsCandidatePatch() async throws {
        let packet = Self.packet()
        let patch = Self.patch(packetId: packet.id)
        let backend = MockGraniteHotSeatBackend(patch: patch)

        let generated = try await GraniteHotSeatGenerator.candidatePatch(
            for: packet,
            using: backend
        )

        XCTAssertEqual(generated, patch)
    }

    func testStringBackendAcceptsFencedCandidatePatchJSON() async throws {
        let packet = Self.packet()
        let patch = Self.patch(packetId: packet.id)
        let data = try JSONEncoder().encode(patch)
        let json = String(decoding: data, as: UTF8.self)
        let backend = StringPatchBackend(output: "```json\n\(json)\n```")

        let generated = try await GraniteHotSeatGenerator.candidatePatch(
            for: packet,
            using: backend
        )

        XCTAssertEqual(generated, patch)
    }

    func testStringBackendRejectsMalformedJSON() async {
        let packet = Self.packet()
        let backend = StringPatchBackend(output: "tourniquet was applied")

        do {
            _ = try await GraniteHotSeatGenerator.candidatePatch(
                for: packet,
                using: backend
            )
            XCTFail("Malformed model output must not become a patch")
        } catch GraniteHotSeatGenerationError.invalidModelOutput {
            // Expected.
        } catch {
            XCTFail("Expected invalidModelOutput, got \(error)")
        }
    }

    func testValidatedPatchRejectsUnknownEvidence() async {
        let packet = Self.packet()
        let patch = Self.patch(packetId: packet.id, evidenceIds: ["seg-missing"])
        let backend = MockGraniteHotSeatBackend(patch: patch)

        do {
            _ = try await GraniteHotSeatGenerator.validatedPatch(
                for: packet,
                using: backend
            )
            XCTFail("Unknown evidence IDs must stop the patch before review")
        } catch GraniteHotSeatGenerationError.validationFailed(let errors) {
            XCTAssertTrue(
                errors.contains(.unknownEvidenceId(factId: "fact-1", evidenceId: "seg-missing"))
            )
        } catch {
            XCTFail("Expected validationFailed, got \(error)")
        }
    }

    func testGeneratedPatchDTOConvertsToCandidatePatch() {
        let generated = GraniteGeneratedCandidatePatch(
            packetId: "packet-1",
            patientId: "PATIENT_1",
            candidateFacts: [
                .init(
                    factId: "fact-1",
                    patientId: "PATIENT_1",
                    domain: "vitals",
                    field: "heartRate",
                    value: "92",
                    evidenceIds: ["seg-1"],
                    confidence: .medium
                )
            ],
            conflicts: [],
            missingRequiredFields: [],
            rejectedInputs: [],
            modelSelfCheck: "schema constrained"
        )

        let patch = generated.makeCandidatePatch()

        XCTAssertEqual(patch.packetId, "packet-1")
        XCTAssertEqual(patch.candidateFacts.first?.confidence, .medium)
        XCTAssertEqual(patch.candidateFacts.first?.evidenceIds, ["seg-1"])
    }

    private static func packet() -> HotSeatPacket {
        let segment = TranscriptSegment(
            id: "seg-1",
            startMs: 0,
            endMs: 2_000,
            textRaw: "heart rate 92",
            textNormalized: "heart rate 92",
            backend: .demo,
            isFinal: true,
            qualityFlags: []
        )
        return HotSeatPacketBuilder.build(
            activePatientId: "PATIENT_1",
            segments: [segment],
            deterministicFacts: [],
            date: Date(timeIntervalSince1970: 0)
        )
    }

    private static func patch(
        packetId: String,
        evidenceIds: [String] = ["seg-1"]
    ) -> GraniteCandidatePatch {
        GraniteCandidatePatch(
            packetId: packetId,
            patientId: "PATIENT_1",
            candidateFacts: [
                .init(
                    id: "fact-1",
                    patientId: "PATIENT_1",
                    domain: "vitals",
                    field: "heartRate",
                    value: "92",
                    evidenceIds: evidenceIds,
                    confidence: .medium
                )
            ],
            conflicts: [],
            missingRequiredFields: [],
            rejectedInputs: [],
            modelSelfCheck: "mock"
        )
    }
}

private struct StringPatchBackend: TCCCLLMBackend {
    let output: String
    let displayName = "String Patch Backend"
    var availability: BackendAvailability = .available

    func generate(instructions: String, prompt: String) async throws -> String {
        output
    }
}
