import Foundation
import TCCCLLM

@Generable
enum GraniteGeneratedConfidence: Sendable, Equatable {
    case high
    case medium
    case low
    case conflict
    case unknown

    var confidence: GraniteConfidence {
        switch self {
        case .high:     .high
        case .medium:   .medium
        case .low:      .low
        case .conflict: .conflict
        case .unknown:  .unknown
        }
    }
}

@Generable
struct GraniteGeneratedCandidateFact: Sendable, Equatable {
    @Guide(description: "Stable candidate fact id such as fact-1")
    var factId: String

    @Guide(description: "Known patient id from the HotSeatPacket")
    var patientId: String

    @Guide(description: "Clinical domain such as march, paws, vitals, medevac, dd1380")
    var domain: String

    @Guide(description: "Allowed schema field name from the packet contract")
    var field: String

    @Guide(description: "Candidate value, or nil when evidence is missing")
    var value: String?

    @Guide(description: "Segment ids that directly support this fact")
    var evidenceIds: [String]

    @Guide(description: "How strongly the packet evidence supports this fact")
    var confidence: GraniteGeneratedConfidence

    func makeCandidateFact() -> GraniteCandidateFact {
        GraniteCandidateFact(
            id: factId,
            patientId: patientId,
            domain: domain,
            field: field,
            value: value,
            evidenceIds: evidenceIds,
            confidence: confidence.confidence
        )
    }
}

@Generable
struct GraniteGeneratedConflict: Sendable, Equatable {
    @Guide(description: "Stable conflict id such as conflict-1")
    var conflictId: String

    @Guide(description: "Known patient id from the HotSeatPacket")
    var patientId: String

    @Guide(description: "Allowed schema field name in conflict")
    var field: String

    @Guide(description: "Conflicting values found in transcript evidence")
    var values: [String]

    @Guide(description: "Segment ids that directly support the conflict")
    var evidenceIds: [String]

    @Guide(description: "Short reason the values should be held for review")
    var reason: String

    func makeConflict() -> GraniteConflict {
        GraniteConflict(
            id: conflictId,
            patientId: patientId,
            field: field,
            values: values,
            evidenceIds: evidenceIds,
            reason: reason
        )
    }
}

@Generable
struct GraniteGeneratedCandidatePatch: Sendable, Equatable {
    @Guide(description: "Exact HotSeatPacket id being answered")
    var packetId: String

    @Guide(description: "Known patient id from the HotSeatPacket")
    var patientId: String

    @Guide(description: "Candidate facts, each with evidence ids")
    var candidateFacts: [GraniteGeneratedCandidateFact]

    @Guide(description: "Conflicts that require operator review")
    var conflicts: [GraniteGeneratedConflict]

    @Guide(description: "Required fields that are still missing")
    var missingRequiredFields: [String]

    @Guide(description: "Transcript segments or inputs rejected as unusable")
    var rejectedInputs: [String]

    @Guide(description: "Brief self-check confirming evidence limits were followed")
    var modelSelfCheck: String

    func makeCandidatePatch() -> GraniteCandidatePatch {
        GraniteCandidatePatch(
            packetId: packetId,
            patientId: patientId,
            candidateFacts: candidateFacts.map { $0.makeCandidateFact() },
            conflicts: conflicts.map { $0.makeConflict() },
            missingRequiredFields: missingRequiredFields,
            rejectedInputs: rejectedInputs,
            modelSelfCheck: modelSelfCheck
        )
    }
}
