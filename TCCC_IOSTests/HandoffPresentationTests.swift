import XCTest
import TCCCDomain
@testable import TCCC_IOS

@MainActor
final class HandoffPresentationTests: XCTestCase {
    private func makeState() async -> AppState {
        let state = AppState()
        await state.processWithEngineForTest("GSW right thigh. Heart rate 110.")
        return state
    }

    func testStructuredZMISTIsAvailableWithoutModelAndUsesVisibleCasualtyID() async throws {
        let state = await makeState()
        let text = state.structuredZMIST
        XCTAssertTrue(text.contains("Z: C-04"))
        XCTAssertTrue(text.contains("M: GSW"))
        XCTAssertTrue(text.contains("HR 110"))
        XCTAssertFalse(text.contains("PATIENT_1"))
        XCTAssertFalse(text.contains("SLM UNAVAILABLE"))
        XCTAssertNil(state.zmistNarrative)
    }

    func testEmptyAssessmentKeepsUnknownsExplicit() {
        let text = AppState().structuredZMIST
        XCTAssertTrue(text.contains("M: UNKNOWN"))
        XCTAssertTrue(text.contains("I: Not recorded"))
        XCTAssertTrue(text.contains("T: Not recorded"))
        XCTAssertTrue(text.contains("HR —"))
        XCTAssertFalse(text.contains("see narrative"))
    }

    func testUnavailableModelLeavesStructuredHandoffVisible() async throws {
        let state = await makeState()
        let expected = state.structuredZMIST
        let request = try XCTUnwrap(state.beginHandoffDraft(.zmist))
        await state.generateHandoffDraft(request, backend: UnavailableHandoffBackend())
        XCTAssertEqual(state.structuredZMIST, expected)
        XCTAssertNil(state.zmistNarrative)
        XCTAssertNotNil(state.handoffDraftError)
        XCTAssertFalse(state.isGeneratingHandoffDraft(.zmist))
    }

    func testCurrentDraftIsAcceptedAndInvalidatedByNewFacts() async throws {
        let state = await makeState()
        let request = try XCTUnwrap(state.beginHandoffDraft(.narrative))
        let accepted = await state.acceptHandoffDraft("Current draft", for: request)
        XCTAssertTrue(accepted)
        XCTAssertEqual(state.encounterNarrative, "Current draft")
        await state.processWithEngineForTest("Heart rate 125.")
        XCTAssertNil(state.encounterNarrative)
    }

    func testLateDraftCannotCrossNewCasualty() async throws {
        let state = await makeState()
        let request = try XCTUnwrap(state.beginHandoffDraft(.narrative))
        await state.newPatient()
        let accepted = await state.acceptHandoffDraft("Prior casualty", for: request)
        XCTAssertFalse(accepted)
        XCTAssertNil(state.encounterNarrative)
        XCTAssertTrue(state.structuredZMIST.contains("Z: C-05"))
    }

    func testLateDraftCannotCrossEndCareEvenWhenCasualtyIDIsReused() async throws {
        let state = await makeState()
        let request = try XCTUnwrap(state.beginHandoffDraft(.zmist))
        let id = state.casualtyId
        await state.endCurrentCare()
        XCTAssertEqual(state.casualtyId, id)
        let accepted = await state.acceptHandoffDraft("Prior casualty", for: request)
        XCTAssertFalse(accepted)
        XCTAssertNil(state.zmistNarrative)
    }

    func testLateDraftCannotUseEngineChangesAwaitingUIRefresh() async throws {
        let state = await makeState()
        let request = try XCTUnwrap(state.beginHandoffDraft(.zmist))
        await state.engine.processTranscript("Heart rate 125.", timestamp: Date())
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 110, "The displayed snapshot has not refreshed yet")
        let accepted = await state.acceptHandoffDraft("Stale HR 110", for: request)
        XCTAssertFalse(accepted)
        XCTAssertNil(state.zmistNarrative)
    }

    func testClearPreventsAnInFlightDraftFromReappearing() async throws {
        let state = await makeState()
        let request = try XCTUnwrap(state.beginHandoffDraft(.zmist))
        state.clearHandoffDrafts()
        let accepted = await state.acceptHandoffDraft("Cleared draft", for: request)
        XCTAssertFalse(accepted)
        XCTAssertNil(state.zmistNarrative)
        XCTAssertFalse(state.isGeneratingHandoffDraft(.zmist))
    }

    func testClearOrNewFactsCannotStartOverlappingInference() async throws {
        for changeFacts in [false, true] {
            let state = await makeState()
            let backend = BlockingHandoffBackend()
            let request = try XCTUnwrap(state.beginHandoffDraft(.narrative))
            let task = Task { await state.generateHandoffDraft(request, backend: backend) }
            await backend.waitUntilStarted()

            if changeFacts {
                await state.processWithEngineForTest("Heart rate 125.")
            } else {
                state.clearHandoffDrafts()
            }

            XCTAssertTrue(state.isGeneratingHandoffDraft(.narrative),
                          "Invalidating text must not claim the model has stopped")
            XCTAssertNil(state.beginHandoffDraft(.narrative),
                         "A second same-kind request must be refused until inference returns")

            await backend.release()
            await task.value
            let calls = await backend.callCount
            XCTAssertEqual(calls, 1)
            XCTAssertFalse(state.isGeneratingHandoffDraft(.narrative))
            XCTAssertNil(state.encounterNarrative, "The invalidated result must still be discarded")

            let retry = try XCTUnwrap(state.beginHandoffDraft(.narrative))
            await state.generateHandoffDraft(retry, backend: UnavailableHandoffBackend())
            XCTAssertFalse(state.isGeneratingHandoffDraft(.narrative))
        }
    }
}

private actor BlockingHandoffBackend: TCCCLLMBackend {
    nonisolated let displayName = "Blocking test model"
    var availability: BackendAvailability { .available }
    private(set) var callCount = 0
    private var resultContinuation: CheckedContinuation<String, Never>?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    func generate(instructions: String, prompt: String) async throws -> String {
        callCount += 1
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
            for waiter in startedWaiters { waiter.resume() }
            startedWaiters.removeAll()
        }
    }

    func waitUntilStarted() async {
        guard callCount == 0 else { return }
        await withCheckedContinuation { startedWaiters.append($0) }
    }

    func release() {
        resultContinuation?.resume(returning: "Old assessment draft")
        resultContinuation = nil
    }
}

private struct UnavailableHandoffBackend: TCCCLLMBackend {
    let displayName = "Unavailable test model"
    var availability: BackendAvailability { .modelNotProvided }
    func generate(instructions: String, prompt: String) async throws -> String {
        XCTFail("An unavailable model must never be invoked")
        throw BackendError.modelNotProvided(backend: displayName)
    }
}
