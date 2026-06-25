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

    /// The current engine value for a (domain, field), via the deterministic
    /// projection — used for contradiction detection and conflict display.
    func currentEngineValue(domain: String, field: String) -> String? {
        guard let p = primaryPatient else { return nil }
        return DeterministicFactProjector.project(p)
            .first { $0.domain == domain && $0.field == field }?.value
    }

    /// Apply one operator-accepted fact, through the engine.
    /// Contradiction check runs BEFORE routing: if the engine already holds a
    /// different value for this (domain, field), the fact is NOT applied — the
    /// engine ground truth holds and `lastConflictMessage` is surfaced for the
    /// operator. An agreeing value (same string) routes normally.
    func acceptGraniteFact(_ accepted: OperatorAcceptedFact, in item: GraniteReviewItem) async {
        let fact = accepted.fact

        // ④ Contradiction → conflict path. Engine ground truth holds; never auto-resolve.
        if let existing = currentEngineValue(domain: fact.domain, field: fact.field),
           let proposed = fact.value, existing != proposed {
            let msg = "GRANITE CONFLICT · \(fact.field): engine '\(existing)' vs model '\(proposed)' · operator override required"
            lastConflictMessage = msg
            appendSystem(msg)
            return   // do NOT apply; engine value holds
        }

        switch FieldRouter.route(domain: fact.domain, field: fact.field, value: fact.value) {
        case .mutation(let write):
            await engine.apply([write], to: fact.patientId)
            await refreshPatientSnapshot()
            appendSystem("GRANITE ACCEPTED · \(fact.field) = \(fact.value ?? "")")
        case .rejected(let reason):
            appendSystem("GRANITE REJECTED · \(fact.field) · \(reason)")
        }
    }

    /// Reject the whole review item: no mutation, drop it from the queue.
    func rejectGraniteReviewItem(_ item: GraniteReviewItem) {
        graniteReviewQueue.removeAll { $0.id == item.id }
        appendSystem("GRANITE REVIEW REJECTED · discarded")
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
