import XCTest
@testable import TCCC_IOS

@MainActor
final class CaptureBackendCoordinatorTests: XCTestCase {
    func testIdleSelectionReleasesOldRecognizerAndInstallsSelectedBackend() async {
        let coordinator = CaptureBackendCoordinator()
        let apple = BackendTestStream(), parakeet = BackendTestStream()
        let factory: CaptureBackendCoordinator.Factory = { $0 == .appleSpeech ? apple : parakeet }
        await coordinator.select(.appleSpeech, factory: factory)
        await coordinator.select(.parakeet, factory: factory)
        XCTAssertEqual(coordinator.installedBackend, .parakeet)
        let releases = await apple.releaseCount
        XCTAssertEqual(releases, 1)
    }

    func testSelectionDuringCaptureAndTailWaitsForLeaseCompletion() async throws {
        let coordinator = CaptureBackendCoordinator()
        let apple = BackendTestStream(), granite = BackendTestStream()
        let factory: CaptureBackendCoordinator.Factory = { $0 == .appleSpeech ? apple : granite }
        let lease = try await coordinator.acquire(.appleSpeech, factory: factory)
        await coordinator.select(.graniteSpeech, factory: factory)
        XCTAssertEqual(coordinator.activeCapture?.backend, .appleSpeech)
        XCTAssertEqual(coordinator.installedBackend, .appleSpeech)
        let releasesBeforeTailEnds = await apple.releaseCount
        XCTAssertEqual(releasesBeforeTailEnds, 0)
        await coordinator.finish(lease.id, factory: factory)
        XCTAssertNil(coordinator.activeCapture)
        XCTAssertEqual(coordinator.installedBackend, .graniteSpeech)
        let releasesAfterTailEnds = await apple.releaseCount
        XCTAssertEqual(releasesAfterTailEnds, 1)
    }

    func testLeaseIsReservedBeforeReplacementAwaits() async throws {
        let coordinator = CaptureBackendCoordinator()
        let apple = BackendTestStream(), parakeet = BackendTestStream()
        let factory: CaptureBackendCoordinator.Factory = { $0 == .appleSpeech ? apple : parakeet }
        let lease = try await coordinator.acquire(.appleSpeech, factory: factory)
        do {
            _ = try await coordinator.acquire(.parakeet, factory: factory)
            XCTFail("A second startup must not replace the in-flight capture")
        } catch TranscriptStreamError.alreadyRunning { }
        XCTAssertTrue(coordinator.isCurrent(lease.id))
        XCTAssertEqual(coordinator.activeCapture?.backend, .appleSpeech)
        await coordinator.finish(lease.id, factory: factory)
    }

    func testRapidSelectionDuringReleaseInstallsOnlyLatestChoice() async {
        let coordinator = CaptureBackendCoordinator()
        let gate = BackendReleaseGate()
        let apple = BackendTestStream(releaseGate: gate)
        var constructed: [AppState.ASRBackend] = []
        let factory: CaptureBackendCoordinator.Factory = { backend in
            constructed.append(backend)
            return backend == .appleSpeech ? apple : BackendTestStream()
        }
        await coordinator.select(.appleSpeech, factory: factory)
        let first = Task { await coordinator.select(.parakeet, factory: factory) }
        await gate.waitUntilEntered()
        let latest = Task { await coordinator.select(.graniteSpeech, factory: factory) }
        for _ in 0..<100 where coordinator.selectedBackend != .graniteSpeech { await Task.yield() }
        XCTAssertEqual(coordinator.selectedBackend, .graniteSpeech)
        await gate.open()
        await first.value
        await latest.value
        XCTAssertEqual(constructed, [.appleSpeech, .graniteSpeech])
        XCTAssertEqual(coordinator.installedBackend, .graniteSpeech)
    }

    func testSelectionWhileStartupAwaitsReleaseDoesNotReplaceReservedCapture() async throws {
        let coordinator = CaptureBackendCoordinator()
        let gate = BackendReleaseGate()
        let apple = BackendTestStream(releaseGate: gate)
        let factory: CaptureBackendCoordinator.Factory = { $0 == .appleSpeech ? apple : BackendTestStream() }
        await coordinator.select(.appleSpeech, factory: factory)
        let startup = Task { try await coordinator.acquire(.parakeet, factory: factory) }
        await gate.waitUntilEntered()
        XCTAssertEqual(coordinator.activeCapture?.backend, .parakeet)
        let nextSelection = Task { await coordinator.select(.graniteSpeech, factory: factory) }
        for _ in 0..<100 where coordinator.selectedBackend != .graniteSpeech { await Task.yield() }
        await gate.open()
        let lease = try await startup.value
        await nextSelection.value
        XCTAssertEqual(lease.backend, .parakeet)
        XCTAssertEqual(coordinator.installedBackend, .parakeet)
        await coordinator.finish(lease.id, factory: factory)
        XCTAssertEqual(coordinator.installedBackend, .graniteSpeech)
    }

    func testShutdownInvalidatesLeaseBeforeReturningAndStaleFinishCannotReplaceNewCapture() async throws {
        let coordinator = CaptureBackendCoordinator()
        let factory: CaptureBackendCoordinator.Factory = { _ in BackendTestStream() }
        let old = try await coordinator.acquire(.appleSpeech, factory: factory)
        await coordinator.shutdown(factory: factory)
        let fresh = try await coordinator.acquire(.parakeet, factory: factory)
        await coordinator.finish(old.id, factory: factory)
        XCTAssertFalse(coordinator.isCurrent(old.id))
        XCTAssertTrue(coordinator.isCurrent(fresh.id))
        XCTAssertEqual(coordinator.installedBackend, .parakeet)
        await coordinator.finish(fresh.id, factory: factory)
    }

    func testInterruptedCaptureReprimesHardwareBeforeTheNextStart() async throws {
        let coordinator = CaptureBackendCoordinator()
        let backend = InterruptedHardwareStream()
        let factory: CaptureBackendCoordinator.Factory = { _ in backend }
        let original = try await coordinator.acquire(.appleSpeech, factory: factory)
        _ = try await backend.start(audioURL: nil)
        await backend.stopImmediate() // logical primed flag survives an iOS interruption
        await coordinator.finish(original.id, factory: factory)
        let resumed = try await coordinator.acquire(.appleSpeech, factory: factory)
        let prepared = try await coordinator.prepare(resumed, restartingAfterInterruption: true)
        _ = try await prepared.start(audioURL: nil)
        let running = await backend.hardwareRunning
        XCTAssertTrue(running)
        await coordinator.finish(resumed.id, factory: factory)
    }

    func testReplacementWaitsForCancellationIgnoringWarmupAndUsesLatestSelection() async throws {
        let coordinator = CaptureBackendCoordinator()
        let gate = BackendReleaseGate()
        let original = BackendTestStream()
        let factory: CaptureBackendCoordinator.Factory = { $0 == .appleSpeech ? original : BackendTestStream() }
        await coordinator.select(.appleSpeech, factory: factory)
        let warmup = Task { await gate.enterAndWait() }
        await gate.waitUntilEntered()
        var requested = AppState.ASRBackend.parakeet
        let startup = Task {
            try await coordinator.acquireAfterWarmup(warmup, selectedBackend: { requested }, factory: factory)
        }
        for _ in 0..<100 where !warmup.isCancelled { await Task.yield() }
        XCTAssertTrue(warmup.isCancelled)
        let releasesBeforeWarmupCompletes = await original.releaseCount
        XCTAssertEqual(releasesBeforeWarmupCompletes, 0)
        XCTAssertEqual(coordinator.installedBackend, .appleSpeech)
        requested = .graniteSpeech
        await gate.open()
        let lease = try await startup.value
        XCTAssertEqual(lease.backend, .graniteSpeech)
        XCTAssertEqual(coordinator.installedBackend, .graniteSpeech)
        await coordinator.finish(lease.id, factory: factory)
    }
}

@MainActor
final class CaptureBackendProvenanceTests: XCTestCase {
    func testSelectingNextBackendCannotRelabelAnActiveCapture() async {
        let state = AppState()
        let generation = state.beginCapture(backend: .appleSpeech)
        state.asrBackend = .parakeet
        await state.receiveAppleCapture(RecognitionUpdate(text: "airway patent", isFinal: true,
            timestamp: Date(), requestID: UUID(), termination: .finalized), generation: generation)
        XCTAssertEqual(state.transcriptLedger.rawSegments.last?.backend, .appleSpeech)

        let next = state.beginCapture(backend: .parakeet)
        await state.receiveAppleCapture(RecognitionUpdate(text: "pulse 80", isFinal: true,
            timestamp: Date(), requestID: UUID(), termination: .finalized), generation: next)
        XCTAssertEqual(state.transcriptLedger.rawSegments.last?.backend, .parakeet)
    }
}

private actor BackendTestStream: TranscriptStream {
    private(set) var releaseCount = 0
    private let releaseGate: BackendReleaseGate?
    init(releaseGate: BackendReleaseGate? = nil) { self.releaseGate = releaseGate }
    func authorize() async throws {}
    func prime() async throws {}
    func unprime() async {
        releaseCount += 1
        await releaseGate?.enterAndWait()
    }
    func start(audioURL: URL?) async throws -> AsyncStream<RecognitionUpdate> { AsyncStream { $0.finish() } }
    func stop() async {}
    func stopImmediate() async {}
}

private actor InterruptedHardwareStream: TranscriptStream {
    private var isPrimed = false
    private(set) var hardwareRunning = false
    func authorize() async throws {}
    func prime() async throws {
        guard !isPrimed else { return }
        isPrimed = true
        hardwareRunning = true
    }
    func unprime() async { isPrimed = false; hardwareRunning = false }
    func start(audioURL: URL?) async throws -> AsyncStream<RecognitionUpdate> {
        if !isPrimed { try await prime() }
        guard hardwareRunning else { throw TranscriptStreamError.engineFailed("Microphone did not restart") }
        return AsyncStream { $0.finish() }
    }
    func stop() async { hardwareRunning = false }
    func stopImmediate() async { hardwareRunning = false }
}

private actor BackendReleaseGate {
    private var entered = false
    private var opened = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    func enterAndWait() async {
        entered = true
        arrival?.resume(); arrival = nil
        if !opened { await withCheckedContinuation { release = $0 } }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { arrival = $0 } }
    }
    func open() {
        opened = true
        release?.resume(); release = nil
    }
}
