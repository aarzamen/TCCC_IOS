import Foundation

struct GraniteValidationArtifact: Codable, Sendable, Equatable {
    let isAccepted: Bool
    let acceptedFactIds: [String]
    let conflictIds: [String]
    let errors: [String]

    init(_ result: GraniteValidationResult) {
        self.isAccepted = result.isAccepted
        self.acceptedFactIds = result.acceptedFacts.map(\.id).sorted()
        self.conflictIds = result.conflicts.map(\.id).sorted()
        self.errors = result.errors.map(Self.describe).sorted()
    }

    private static func describe(_ error: GraniteValidationError) -> String {
        switch error {
        case .unknownPatient(let patientId):
            return "unknownPatient:\(patientId)"
        case .emptyPatch:
            return "emptyPatch"
        case .missingEvidenceIds(let factId):
            return "missingEvidenceIds:\(factId)"
        case .unknownEvidenceId(let factId, let evidenceId):
            return "unknownEvidenceId:\(factId):\(evidenceId)"
        case .unknownField(let field):
            return "unknownField:\(field)"
        case .impossibleValue(let field, let value):
            return "impossibleValue:\(field):\(value)"
        }
    }
}

struct GraniteReviewItemArtifact: Codable, Sendable, Equatable {
    let createdAtUTC: Date
    let status: String
    let patch: GraniteCandidatePatch
    let validation: GraniteValidationArtifact

    init(
        patch: GraniteCandidatePatch,
        validation: GraniteValidationResult,
        createdAt: Date
    ) {
        self.createdAtUTC = createdAt
        self.status = validation.isAccepted
            ? GraniteReviewStatus.readyForOperatorReview.rawValue
            : GraniteReviewStatus.heldForValidation.rawValue
        self.patch = patch
        self.validation = GraniteValidationArtifact(validation)
    }
}

struct GraniteParsedCandidatePatchArtifact: Codable, Sendable, Equatable {
    let parsed: Bool
    let patch: GraniteCandidatePatch?
    let error: String?
}

struct GraniteRealModelMetrics: Codable, Sendable, Equatable {
    let runId: String
    let modelId: String
    let modelDirectory: String
    let deviceName: String
    let startedAtUTC: Date
    let finishedAtUTC: Date
    let coldLoadAndGenerationMs: Int
    let parseAndValidationMs: Int
    let rawOutputCharacterCount: Int
    let availableMemoryBeforeBytes: UInt64?
    let availableMemoryAfterBytes: UInt64?
    let thermalState: String
    let status: String
}

struct GraniteRealModelRunResult: Sendable, Equatable {
    let runId: String
    let modelId: String
    let modelDirectory: String
    let packet: HotSeatPacket
    let prompt: String
    let rawModelOutput: String
    let parsedPatch: GraniteCandidatePatch?
    let parseError: String?
    let validation: GraniteValidationArtifact
    let reviewItem: GraniteReviewItemArtifact?
    let metrics: GraniteRealModelMetrics
}

enum GraniteRealModelRunner {
    static func run(
        packet: HotSeatPacket,
        backend: any TCCCLLMBackend,
        modelId: String = GraniteTextLLMBackend.modelId,
        modelDirectory: String? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) async throws -> GraniteRealModelRunResult {
        let runId = "granite-real-\(UUID().uuidString)"
        let prompt = try GranitePromptBuilder.prompt(for: packet)
        let startedAt = now()
        let memoryBefore = MemoryStat.availableBytes()
        let generationStart = ContinuousClock.now
        let rawOutput = try await backend.generate(
            instructions: GraniteHotSeatGenerator.instructions,
            prompt: prompt
        )
        let generationEnd = ContinuousClock.now

        let parseStart = ContinuousClock.now
        let parsedPatch: GraniteCandidatePatch?
        let parseError: String?
        do {
            parsedPatch = try GraniteHotSeatGenerator.decodeCandidatePatch(from: rawOutput)
            parseError = nil
        } catch {
            parsedPatch = nil
            parseError = "\(error)"
        }

        let validationResult: GraniteValidationResult
        let reviewItem: GraniteReviewItemArtifact?
        if let parsedPatch {
            validationResult = GraniteSchemaValidator.validate(
                parsedPatch,
                knownEvidenceIds: Set(packet.segments.map(\.id)),
                knownPatientIds: Set(packet.knownPatientIds)
            )
            reviewItem = GraniteReviewItemArtifact(
                patch: parsedPatch,
                validation: validationResult,
                createdAt: now()
            )
        } else {
            validationResult = GraniteValidationResult(
                acceptedFacts: [],
                conflicts: [],
                errors: [.unknownField(field: "invalidModelOutput")]
            )
            reviewItem = nil
        }
        let parseEnd = ContinuousClock.now
        let finishedAt = now()
        let memoryAfter = MemoryStat.availableBytes()

        let status: String
        if parsedPatch == nil {
            status = "parse_failed"
        } else if validationResult.isAccepted {
            status = "accepted"
        } else {
            status = "held_for_validation"
        }

        let metrics = GraniteRealModelMetrics(
            runId: runId,
            modelId: modelId,
            modelDirectory: modelDirectory ?? "",
            deviceName: ProcessInfo.processInfo.hostName,
            startedAtUTC: startedAt,
            finishedAtUTC: finishedAt,
            coldLoadAndGenerationMs: milliseconds(from: generationStart, to: generationEnd),
            parseAndValidationMs: milliseconds(from: parseStart, to: parseEnd),
            rawOutputCharacterCount: rawOutput.count,
            availableMemoryBeforeBytes: memoryBefore,
            availableMemoryAfterBytes: memoryAfter,
            thermalState: thermalLabel(),
            status: status
        )

        return GraniteRealModelRunResult(
            runId: runId,
            modelId: modelId,
            modelDirectory: modelDirectory ?? "",
            packet: packet,
            prompt: prompt,
            rawModelOutput: rawOutput,
            parsedPatch: parsedPatch,
            parseError: parseError,
            validation: GraniteValidationArtifact(validationResult),
            reviewItem: reviewItem,
            metrics: metrics
        )
    }

    private static func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant
    ) -> Int {
        let duration = start.duration(to: end)
        let components = duration.components
        let seconds = Int(components.seconds) * 1_000
        let attoseconds = components.attoseconds / 1_000_000_000_000_000
        return seconds + Int(attoseconds)
    }

    private static func thermalLabel() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }
}
