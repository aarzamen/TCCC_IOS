import Foundation
import Observation

/// Owns recognizer replacement separately from an utterance or its finalization.
/// A capture lease includes startup, recording, and the entire finishing tail.
@MainActor @Observable
final class CaptureBackendCoordinator {
    typealias Factory = @MainActor (AppState.ASRBackend) -> any TranscriptStream

    struct Lease: Equatable {
        let id: UUID
        let backend: AppState.ASRBackend
    }

    private(set) var selectedBackend: AppState.ASRBackend = .appleSpeech
    private(set) var installedBackend: AppState.ASRBackend?
    private(set) var activeCapture: Lease?
    private(set) var recognizer: (any TranscriptStream)?
    private var enabled = false
    @ObservationIgnored private var replacementTask: Task<Void, Never>?

    func select(_ backend: AppState.ASRBackend, factory: @escaping Factory) async {
        selectedBackend = backend
        enabled = true
        await reconcile(factory: factory)
    }

    func acquire(_ backend: AppState.ASRBackend, factory: @escaping Factory) async throws -> Lease {
        guard activeCapture == nil else { throw TranscriptStreamError.alreadyRunning }
        let lease = Lease(id: UUID(), backend: backend)
        activeCapture = lease // reserve before the first suspension, including startup
        selectedBackend = backend
        enabled = true
        await reconcile(factory: factory)
        guard isCurrent(lease.id), installedBackend == backend else { throw CancellationError() }
        return lease
    }

    /// Idle warm-up may ignore cancellation while a model loads. Join it before
    /// retiring its recognizer, then reserve the operator's latest selection.
    func acquireAfterWarmup(_ warmup: Task<Void, Never>?,
                            selectedBackend: @MainActor () -> AppState.ASRBackend,
                            isValid: @MainActor () -> Bool = { true },
                            factory: @escaping Factory) async throws -> Lease {
        warmup?.cancel()
        await warmup?.value
        guard !Task.isCancelled, isValid() else { throw CancellationError() }
        return try await acquire(selectedBackend(), factory: factory)
    }

    /// An interruption can stop hardware while a backend still considers itself
    /// primed. Reset the actual leased backend before restarting its microphone.
    func prepare(_ lease: Lease, restartingAfterInterruption: Bool,
                 isValid: @MainActor () -> Bool = { true }) async throws -> any TranscriptStream {
        func checkLease() throws {
            guard isCurrent(lease.id), !Task.isCancelled, isValid() else { throw CancellationError() }
        }
        try checkLease()
        guard let recognizer else { throw CancellationError() }
        try await recognizer.authorize()
        try checkLease()
        if restartingAfterInterruption {
            await recognizer.unprime()
            try checkLease()
            try await recognizer.prime()
            try checkLease()
        }
        return recognizer
    }

    func isCurrent(_ id: UUID) -> Bool { activeCapture?.id == id }

    func finish(_ id: UUID, factory: @escaping Factory) async {
        guard isCurrent(id) else { return }
        activeCapture = nil
        await reconcile(factory: factory)
    }

    func shutdown(factory: @escaping Factory) async {
        enabled = false
        activeCapture = nil
        await reconcile(factory: factory)
    }

    private var desiredBackend: AppState.ASRBackend? {
        enabled ? (activeCapture?.backend ?? selectedBackend) : nil
    }

    private func reconcile(factory: @escaping Factory) async {
        // Every waiter shares one replacement operation. Choices made while
        // unprime is suspended are coalesced into the latest desired backend.
        while let pending = replacementTask { await pending.value }
        guard installedBackend != desiredBackend else { return }
        let task = Task { @MainActor in
            defer { replacementTask = nil }
            let retiring = recognizer
            recognizer = nil
            installedBackend = nil
            await retiring?.stopImmediate()
            await retiring?.unprime()
            guard let backend = desiredBackend else { return }
            recognizer = factory(backend)
            installedBackend = backend
        }
        replacementTask = task
        await task.value
    }
}
