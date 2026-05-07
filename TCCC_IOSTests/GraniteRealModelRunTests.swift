import XCTest
@testable import TCCC_IOS

@MainActor
final class GraniteRealModelRunTests: XCTestCase {
    func testFixturePacketContainsMalformedInputCases() throws {
        let packet = GraniteRealModelFixtures.malformedCareNarrationPacket()

        XCTAssertEqual(packet.activePatientId, "PATIENT_1")
        XCTAssertEqual(packet.segments.map(\.id), ["seg-1", "seg-3", "seg-4", "seg-5"])
        XCTAssertTrue(packet.blockedActions.contains(.downloadModelWeights))
        XCTAssertTrue(packet.segments.contains { $0.qualityFlags.contains(.instructionLikeContent) })
        XCTAssertTrue(packet.segments.contains { $0.qualityFlags.contains(.duplicateCollapsed) })
    }

    func testModelAssetGateRejectsMissingExplicitDirectory() {
        let missing = URL(fileURLWithPath: "/tmp/tccc-missing-granite-\(UUID().uuidString)")
        let report = GraniteLocalModelAssetGate.validate(modelDirectory: missing)

        XCTAssertFalse(report.isUsable)
        XCTAssertTrue(report.failures.contains(.directoryMissing(missing.path)))
    }

    func testArtifactWriterPersistsFullRunBundle() async throws {
        let packet = GraniteRealModelFixtures.malformedCareNarrationPacket()
        let patch = GraniteCandidatePatch(
            packetId: packet.id,
            patientId: "PATIENT_1",
            candidateFacts: [
                .init(
                    id: "fact-hr-1",
                    patientId: "PATIENT_1",
                    domain: "vitals",
                    field: "heartRate",
                    value: "118",
                    evidenceIds: ["seg-4"],
                    confidence: .medium
                )
            ],
            conflicts: [],
            missingRequiredFields: ["location"],
            rejectedInputs: ["seg-3"],
            modelSelfCheck: "Only one candidate fact had direct evidence."
        )
        let rawOutput = String(decoding: try JSONEncoder().encode(patch), as: UTF8.self)
        let result = GraniteRealModelRunResult(
            runId: "test-run",
            modelId: GraniteTextLLMBackend.modelId,
            modelDirectory: "/tmp/granite-local",
            packet: packet,
            prompt: try GranitePromptBuilder.prompt(for: packet),
            rawModelOutput: rawOutput,
            parsedPatch: patch,
            parseError: nil,
            validation: .init(
                GraniteSchemaValidator.validate(
                    patch,
                    knownEvidenceIds: Set(packet.segments.map(\.id)),
                    knownPatientIds: Set(packet.knownPatientIds)
                )
            ),
            reviewItem: .init(
                patch: patch,
                validation: GraniteSchemaValidator.validate(
                    patch,
                    knownEvidenceIds: Set(packet.segments.map(\.id)),
                    knownPatientIds: Set(packet.knownPatientIds)
                ),
                createdAt: Date(timeIntervalSince1970: 0)
            ),
            metrics: .init(
                runId: "test-run",
                modelId: GraniteTextLLMBackend.modelId,
                modelDirectory: "/tmp/granite-local",
                deviceName: "unit-test",
                startedAtUTC: Date(timeIntervalSince1970: 0),
                finishedAtUTC: Date(timeIntervalSince1970: 1),
                coldLoadAndGenerationMs: 1_000,
                parseAndValidationMs: 10,
                rawOutputCharacterCount: rawOutput.count,
                availableMemoryBeforeBytes: nil,
                availableMemoryAfterBytes: nil,
                thermalState: "nominal",
                status: "accepted"
            )
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("granite-artifacts-\(UUID().uuidString)", isDirectory: true)

        let folder = try GraniteRealModelArtifactWriter.write(result, to: root)

        let expectedFiles = [
            "packet.json",
            "prompt.txt",
            "raw_model_output.txt",
            "parsed_candidate_patch.json",
            "validator_result.json",
            "review_queue_item.json",
            "metrics.json",
            "README.md"
        ]
        for file in expectedFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: folder.appendingPathComponent(file).path),
                "\(file) should be written"
            )
        }
    }

    func testManualRealModelRunProducesArtifactsWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard Self.environmentValue("TCCC_RUN_REAL_MODEL", in: environment) == "1" else {
            throw XCTSkip("Set TCCC_RUN_REAL_MODEL=1 to run real Granite inference.")
        }

        guard let modelPath = Self.environmentValue("TCCC_GRANITE_MODEL_DIR", in: environment),
              !modelPath.isEmpty else {
            XCTFail("TCCC_GRANITE_MODEL_DIR must point at explicit local Granite weights.")
            return
        }

        let modelDirectory = URL(fileURLWithPath: modelPath, isDirectory: true)
        let report = GraniteLocalModelAssetGate.validate(modelDirectory: modelDirectory)
        XCTAssertTrue(report.isUsable, report.failures.map(\.description).joined(separator: "\n"))

        let resultRoot = URL(
            fileURLWithPath: Self.environmentValue("TCCC_REAL_MODEL_RESULTS_DIR", in: environment)
                ?? "/Users/ama/.codex/worktrees/b727/TCCC_IOS/artifacts/granite-runs",
            isDirectory: true
        )
        let backend = GraniteLocalTextLLMBackend(modelDirectory: modelDirectory)
        let packet = GraniteRealModelFixtures.malformedCareNarrationPacket()

        let result = try await GraniteRealModelRunner.run(packet: packet, backend: backend)
        let folder = try GraniteRealModelArtifactWriter.write(result, to: resultRoot)

        XCTAssertFalse(result.rawModelOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("raw_model_output.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("validator_result.json").path))
    }

    private static func environmentValue(
        _ key: String,
        in environment: [String: String]
    ) -> String? {
        environment[key] ?? environment["SIMCTL_CHILD_\(key)"]
    }
}
