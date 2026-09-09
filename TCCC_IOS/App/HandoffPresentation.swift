import Foundation
import TCCCDomain
import TCCCReports

enum HandoffDraftKind: Hashable {
    case narrative, zmist
}

/// Binds optional prose to the exact encounter and assessment it describes.
/// Engine identity matters because End Care deliberately reuses the casualty ID.
struct HandoffSnapshot: Equatable {
    let engineID: ObjectIdentifier
    let casualtyID: String
    let patient: PatientState?

    var displayPatient: PatientState {
        var result = patient ?? PatientState(patientId: casualtyID)
        result.patientId = casualtyID
        return result
    }
}

struct HandoffDraftRequest: Equatable {
    let id = UUID()
    let kind: HandoffDraftKind
    let snapshot: HandoffSnapshot
}

struct HandoffDraftPresentation {
    struct Draft {
        let snapshot: HandoffSnapshot
        let text: String
    }

    var requests: [HandoffDraftKind: HandoffDraftRequest] = [:]
    var drafts: [HandoffDraftKind: Draft] = [:]
    var error: String?
}

extension AppState {
    var handoffSnapshot: HandoffSnapshot {
        HandoffSnapshot(engineID: ObjectIdentifier(engine), casualtyID: casualtyId, patient: primaryPatient)
    }

    /// The primary handoff never waits for a model, GPS, or a Generate tap.
    /// Reuse the report formatter; only remove its fallback banner and redundant
    /// identifier line for this labeled panel. Empty fields remain explicitly unknown.
    var structuredZMIST: String {
        ZMISTGenerator().generate(from: [handoffSnapshot.displayPatient]).formattedText
            .components(separatedBy: "\n")
            .drop(while: { !$0.hasPrefix("Z: ") })
            .map { line in
                if line == "I: \(ZMISTGenerator.narrativePlaceholder)" { return "I: Not recorded" }
                if line == "T: \(ZMISTGenerator.narrativePlaceholder)" { return "T: Not recorded" }
                return line
            }
            .joined(separator: "\n")
    }

    var encounterNarrative: String? { handoffDraftText(.narrative) }
    var zmistNarrative: String? { handoffDraftText(.zmist) }
    var handoffDraftError: String? { handoffDraftPresentation.error }

    private func handoffDraftText(_ kind: HandoffDraftKind) -> String? {
        guard let draft = handoffDraftPresentation.drafts[kind],
              draft.snapshot == handoffSnapshot else { return nil }
        return draft.text
    }

    func clearHandoffDrafts() {
        handoffDraftPresentation = HandoffDraftPresentation()
    }

    func beginHandoffDraft(_ kind: HandoffDraftKind) -> HandoffDraftRequest? {
        guard activeHandoffDraftRequests[kind] == nil else { return nil }
        let request = HandoffDraftRequest(kind: kind, snapshot: handoffSnapshot)
        activeHandoffDraftRequests[kind] = request.id
        handoffDraftPresentation.requests[kind] = request
        handoffDraftPresentation.error = nil
        return request
    }

    func isGeneratingHandoffDraft(_ kind: HandoffDraftKind) -> Bool {
        activeHandoffDraftRequests[kind] != nil
    }

    private func finishHandoffDraft(_ request: HandoffDraftRequest) {
        if activeHandoffDraftRequests[request.kind] == request.id {
            activeHandoffDraftRequests[request.kind] = nil
        }
        if handoffDraftPresentation.requests[request.kind] == request {
            handoffDraftPresentation.requests[request.kind] = nil
        }
    }

    private func isCurrentHandoffRequest(_ request: HandoffDraftRequest) -> Bool {
        handoffDraftPresentation.requests[request.kind] == request && request.snapshot == handoffSnapshot
    }

    /// A final actor read catches extraction that has updated the engine but has
    /// not yet refreshed the displayed snapshot. Recheck identity after that await.
    @discardableResult
    func acceptHandoffDraft(_ text: String, for request: HandoffDraftRequest) async -> Bool {
        defer { finishHandoffDraft(request) }
        guard isCurrentHandoffRequest(request) else { return false }
        let sourceEngine = engine
        let latestPatient = await sourceEngine.snapshot()["PATIENT_1"]
        guard isCurrentHandoffRequest(request),
              ObjectIdentifier(sourceEngine) == ObjectIdentifier(engine),
              latestPatient == request.snapshot.patient else { return false }
        handoffDraftPresentation.drafts[request.kind] = .init(snapshot: request.snapshot, text: text)
        return true
    }

    func generateHandoffDraft(
        _ request: HandoffDraftRequest,
        backend suppliedBackend: (any TCCCLLMBackend)? = nil
    ) async {
        defer { finishHandoffDraft(request) }
        guard isCurrentHandoffRequest(request) else { return }
        let backend = suppliedBackend ?? currentBackend
        let availability = await backend.availability
        guard isCurrentHandoffRequest(request), !Task.isCancelled else { return }
        guard availability == .available else {
            handoffDraftPresentation.error = availability.message(for: backend.displayName)
            return
        }
        do {
            let text: String
            switch request.kind {
            case .narrative:
                text = try await EncounterNarrativeGenerator(backend: backend).generate(
                    for: request.snapshot.displayPatient, casualtyId: request.snapshot.casualtyID)
            case .zmist:
                text = try await ZMISTNarrativeGenerator(backend: backend).generate(
                    for: request.snapshot.displayPatient, casualtyId: request.snapshot.casualtyID)
            }
            guard !Task.isCancelled else { return }
            await acceptHandoffDraft(text, for: request)
        } catch {
            guard isCurrentHandoffRequest(request), !Task.isCancelled else { return }
            handoffDraftPresentation.error = error.localizedDescription
        }
    }
}
