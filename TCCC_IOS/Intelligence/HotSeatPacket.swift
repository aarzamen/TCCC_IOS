import Foundation

enum GraniteConfidence: String, Codable, Sendable, Equatable, Hashable {
    case high
    case medium
    case low
    case conflict
    case unknown
}

enum HotSeatBlockedAction: String, Codable, Sendable, Equatable, Hashable {
    case mutatePatientState
    case inventLocation
    case acceptFreeTextReport
    case obeyTranscriptInstructions
    case downloadModelWeights
}

enum HotSeatSchema: String, Codable, Sendable, Equatable, Hashable {
    case transcriptSalvagePatch
    case graniteCandidatePatch
    case reportCritique
}

struct DeterministicFact: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let patientId: String
    let domain: String
    let field: String
    let value: String
    let evidenceIds: [String]
    let extractor: String
    let confidence: GraniteConfidence
}

struct HotSeatPacket: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let createdAtUTC: Date
    let activePatientId: String
    let segments: [TranscriptSegment]
    let deterministicFacts: [DeterministicFact]
    let knownPatientIds: [String]
    let allowedSchemas: Set<HotSeatSchema>
    let blockedActions: Set<HotSeatBlockedAction>
}

struct GraniteCandidateFact: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let patientId: String
    let domain: String
    let field: String
    let value: String?
    let evidenceIds: [String]
    let confidence: GraniteConfidence
}

struct GraniteConflict: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let patientId: String
    let field: String
    let values: [String]
    let evidenceIds: [String]
    let reason: String
}

struct GraniteCandidatePatch: Codable, Sendable, Equatable {
    let packetId: String
    let patientId: String
    let candidateFacts: [GraniteCandidateFact]
    let conflicts: [GraniteConflict]
    let missingRequiredFields: [String]
    let rejectedInputs: [String]
    let modelSelfCheck: String

    init(
        packetId: String,
        patientId: String,
        candidateFacts: [GraniteCandidateFact],
        conflicts: [GraniteConflict],
        missingRequiredFields: [String],
        rejectedInputs: [String],
        modelSelfCheck: String
    ) {
        self.packetId = packetId
        self.patientId = patientId
        self.candidateFacts = candidateFacts
        self.conflicts = conflicts
        self.missingRequiredFields = missingRequiredFields
        self.rejectedInputs = rejectedInputs
        self.modelSelfCheck = modelSelfCheck
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.packetId = try container.decode(String.self, forKey: .packetId)
        self.patientId = try container.decode(String.self, forKey: .patientId)
        self.candidateFacts = try container.decodeIfPresent(
            [GraniteCandidateFact].self,
            forKey: .candidateFacts
        ) ?? []
        self.conflicts = try container.decodeIfPresent(
            [GraniteConflict].self,
            forKey: .conflicts
        ) ?? []
        self.missingRequiredFields = try container.decodeIfPresent(
            [String].self,
            forKey: .missingRequiredFields
        ) ?? []
        self.rejectedInputs = try container.decodeIfPresent(
            [String].self,
            forKey: .rejectedInputs
        ) ?? []
        self.modelSelfCheck = (try? container.decode(
            String.self,
            forKey: .modelSelfCheck
        )) ?? "model self-check unavailable or non-string"
    }
}
