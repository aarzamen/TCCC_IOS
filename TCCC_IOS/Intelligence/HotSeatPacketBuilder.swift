import Foundation

enum HotSeatPacketBuilder {
    static func build(
        activePatientId: String,
        segments: [TranscriptSegment],
        deterministicFacts: [DeterministicFact],
        date: Date = Date()
    ) -> HotSeatPacket {
        let knownIds = Set([activePatientId] + deterministicFacts.map(\.patientId))

        return HotSeatPacket(
            id: "hotseat-\(UUID().uuidString)",
            createdAtUTC: date,
            activePatientId: activePatientId,
            segments: segments,
            deterministicFacts: deterministicFacts,
            knownPatientIds: Array(knownIds).sorted(),
            allowedSchemas: [.transcriptSalvagePatch, .graniteCandidatePatch],
            blockedActions: [
                .mutatePatientState,
                .inventLocation,
                .acceptFreeTextReport,
                .obeyTranscriptInstructions,
                .downloadModelWeights
            ]
        )
    }
}
