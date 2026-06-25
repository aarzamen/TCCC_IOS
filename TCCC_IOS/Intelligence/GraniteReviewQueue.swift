import Foundation
import TCCCDomain

enum GraniteReviewStatus: String, Sendable, Equatable {
    case readyForOperatorReview
    case heldForValidation
}

struct GraniteReviewItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let createdAt: Date
    let patch: GraniteCandidatePatch
    let validation: GraniteValidationResult

    var status: GraniteReviewStatus {
        validation.isAccepted ? .readyForOperatorReview : .heldForValidation
    }
}

extension AppState {
    func runGraniteHotSeatReview() async {
        await runGraniteHotSeatReview(using: currentBackend)
    }

    func runGraniteHotSeatReview(using backend: any TCCCLLMBackend) async {
        let segments = transcriptLedger.normalizedSegments
        guard !segments.isEmpty else {
            appendSystem("GRANITE REVIEW HELD · no transcript evidence")
            return
        }

        let activePatientId = primaryPatient?.patientId ?? "PATIENT_1"
        let packet = HotSeatPacketBuilder.build(
            activePatientId: activePatientId,
            segments: segments,
            deterministicFacts: DeterministicFactProjector.project(
                primaryPatient ?? PatientState(patientId: activePatientId)),
            date: Date()
        )

        do {
            let patch = try await GraniteHotSeatGenerator.candidatePatch(
                for: packet,
                using: backend
            )
            applyGraniteCandidatePatchForReview(
                patch,
                knownEvidenceIds: Set(packet.segments.map(\.id)),
                knownPatientIds: Set(packet.knownPatientIds)
            )
        } catch GraniteHotSeatGenerationError.backendUnavailable(let availability) {
            appendSystem("GRANITE REVIEW UNAVAILABLE · \(availability.message(for: backend.displayName))")
        } catch GraniteHotSeatGenerationError.invalidModelOutput {
            appendSystem("GRANITE REVIEW HELD · invalid model output")
        } catch GraniteHotSeatGenerationError.validationFailed(let errors) {
            appendSystem("GRANITE REVIEW HELD · \(errors.count) validation errors")
        } catch {
            appendSystem("GRANITE REVIEW HELD · \(error.localizedDescription)")
        }
    }

    func applyGraniteCandidatePatchForReview(
        _ patch: GraniteCandidatePatch,
        knownEvidenceIds: Set<String>,
        knownPatientIds: Set<String>,
        date: Date = Date()
    ) {
        let validation = GraniteSchemaValidator.validate(
            patch,
            knownEvidenceIds: knownEvidenceIds,
            knownPatientIds: knownPatientIds
        )

        graniteReviewQueue.append(
            GraniteReviewItem(
                id: UUID(),
                createdAt: date,
                patch: patch,
                validation: validation
            )
        )

        if validation.isAccepted {
            appendSystem("GRANITE REVIEW READY · operator verification required")
        } else {
            appendSystem("GRANITE REVIEW HELD · validation failed")
        }
    }
}
