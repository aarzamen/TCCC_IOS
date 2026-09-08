import XCTest
import Speech
@testable import TCCC_IOS

/// Deterministic synthetic-event tests for the benchmark run-state helper
/// that `AppleSpeechFileTranscriber` must consume (Task 2, capture-reliability
/// sprint). No Speech framework, model, microphone, or network involved —
/// every test drives `SpeechFileRunState` with a hand-built callback sequence
/// and asserts the completion evidence the actor is required to surface.
///
/// Contract under test (spec: docs/superpowers/specs/2026-09-07-capture-reliability-design.md):
///   - Timeout/error/cancellation after partials retain the partial text but
///     are never reported as recognizer finalization.
///   - Exactly one completion per run; late events after completion are inert.
///   - Events carrying a stale run ID cannot mutate a newer run.
///   - An overlapping begin is rejected without overwriting the active run.
///   - Cumulative hypotheses replace within an utterance; timed utterances accumulate.
///   - Finalization is recognizer evidence only — none of these tests assert
///     whole-file coverage from a `.finalized` termination.
final class AppleSpeechFileTranscriberTests: XCTestCase {

    func testRequestsPreservePunctuationForSentenceScopedExtraction() {
        let requests: [SFSpeechRecognitionRequest] = [
            SpeechRequestFactory.makeBufferRequest(),
            SpeechRequestFactory.makeURLRequest(url: URL(fileURLWithPath: "/tmp/synthetic.wav"))
        ]
        for request in requests {
            XCTAssertTrue(request.addsPunctuation)
            XCTAssertTrue(request.requiresOnDeviceRecognition)
            XCTAssertTrue(request.shouldReportPartialResults)
        }
    }

    func testTimedUtterancesSurviveResetsAndNilFinalCallback() {
        var run = startedRun()
        _ = run.ingestCallback(text: "pulse 120", isFinal: false, errorReason: nil,
            runID: run.runID, at: t1, speechStart: 7.83, speechDuration: 26.73)
        _ = run.ingestCallback(text: "blood", isFinal: false, errorReason: nil,
            runID: run.runID, at: t2, segmentStart: 0, segmentEnd: 0)
        _ = run.ingestCallback(text: "blood pressure 90 over 60", isFinal: false, errorReason: nil,
            runID: run.runID, at: t3, speechStart: 34.56, speechDuration: 22.53)
        let result = run.ingestCallback(text: nil, isFinal: true, errorReason: nil,
            runID: run.runID, at: t4)
        XCTAssertEqual(result?.transcript, "pulse 120 blood pressure 90 over 60")
        XCTAssertEqual(result?.termination, .finalized)
        XCTAssertEqual(result?.callbackCount, 4)
    }

    func testErrorRetainsEarlierUtteranceAndLatestPartial() {
        var run = startedRun()
        _ = run.ingestCallback(text: "tourniquet applied", isFinal: false, errorReason: nil,
            runID: run.runID, at: t1, speechStart: 1, speechDuration: 3)
        let result = run.ingestCallback(text: "pulse weak", isFinal: true, errorReason: "interrupted",
            runID: run.runID, at: t2)
        XCTAssertEqual(result?.transcript, "tourniquet applied pulse weak")
        XCTAssertEqual(result?.termination, .failed)
        XCTAssertEqual(result?.isComplete, false)
    }

    func testStaleTimedUtteranceCannotChangeCurrentRun() {
        var run = startedRun()
        _ = run.ingestCallback(text: "current patient", isFinal: false, errorReason: nil,
            runID: run.runID, at: t1, speechStart: 1, speechDuration: 3)
        XCTAssertNil(run.ingestCallback(text: "other patient", isFinal: true, errorReason: nil,
            runID: UUID(), at: t2, speechStart: 5, speechDuration: 3))
        XCTAssertEqual(run.latestHypothesis, "current patient")
        XCTAssertEqual(run.cancel(runID: run.runID, at: t3)?.transcript, "current patient")
    }

    // Fixed synthetic clock values so timing evidence is assertable.
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private var t1: Date { t0.addingTimeInterval(1) }
    private var t2: Date { t0.addingTimeInterval(2) }
    private var t3: Date { t0.addingTimeInterval(3) }
    private var t4: Date { t0.addingTimeInterval(4) }

    private func startedRun(at date: Date? = nil) -> SpeechFileRunState {
        switch SpeechFileRunState.begin(replacing: nil, at: date ?? t0) {
        case .started(let run): return run
        case .rejectedActiveRun: XCTFail("begin(replacing: nil) must start a run"); fatalError()
        }
    }

    // MARK: - Partial then non-final termination: text retained, marked incomplete

    func testPartialThenTimeoutRetainsTextButIsIncomplete() {
        var run = startedRun()
        XCTAssertNil(run.ingestHypothesis("massive hemorrhage right", isFinal: false, runID: run.runID, at: t1))
        let completion = run.fireTimeout(runID: run.runID, at: t3)

        XCTAssertEqual(completion?.termination, .timedOut)
        XCTAssertEqual(completion?.transcript, "massive hemorrhage right")
        XCTAssertEqual(completion?.isComplete, false,
                       "Timeout after partials must retain evidence but never claim finalization")
        XCTAssertEqual(completion?.callbackCount, 1)
        XCTAssertEqual(completion?.firstHypothesisAt, t1)
        XCTAssertEqual(completion?.finishedAt, t3)
    }

    func testPartialThenErrorRetainsTextReportsErrorAndIsIncomplete() {
        var run = startedRun()
        XCTAssertNil(run.ingestHypothesis("tourniquet applied", isFinal: false, runID: run.runID, at: t1))
        let completion = run.ingestError(reason: "Recognition service disconnected", runID: run.runID, at: t2)

        XCTAssertEqual(completion?.termination, .failed)
        XCTAssertEqual(completion?.transcript, "tourniquet applied",
                       "Partial evidence must survive an error, not be discarded")
        XCTAssertEqual(completion?.isComplete, false,
                       "An error after partials is not success — current production maps this to success")
        XCTAssertEqual(completion?.failureReason, "Recognition service disconnected")
    }

    func testPartialThenCancelRetainsTextButIsIncomplete() {
        var run = startedRun()
        XCTAssertNil(run.ingestHypothesis("airway patent", isFinal: false, runID: run.runID, at: t1))
        let completion = run.cancel(runID: run.runID, at: t2)

        XCTAssertEqual(completion?.termination, .cancelled)
        XCTAssertEqual(completion?.transcript, "airway patent")
        XCTAssertEqual(completion?.isComplete, false)
    }

    func testErrorWithNoPartialsFailsWithEmptyTranscript() {
        var run = startedRun()
        let completion = run.ingestError(reason: "no speech detected", runID: run.runID, at: t1)

        XCTAssertEqual(completion?.termination, .failed)
        XCTAssertEqual(completion?.transcript, "")
        XCTAssertEqual(completion?.isComplete, false)
        XCTAssertEqual(completion?.failureReason, "no speech detected")
    }

    // MARK: - Single completion: later events are inert

    func testFinalCompletionThenLateTimeoutIsIgnored() {
        var run = startedRun()
        let completion = run.ingestHypothesis("patient stable", isFinal: true, runID: run.runID, at: t1)
        XCTAssertEqual(completion?.termination, .finalized)
        XCTAssertEqual(completion?.transcript, "patient stable")
        XCTAssertEqual(completion?.isComplete, true)

        // Cancelled-timer race: the timeout still fires against a finished run.
        XCTAssertNil(run.fireTimeout(runID: run.runID, at: t3),
                     "A timeout after finalization must not produce a second completion")
        XCTAssertEqual(run.completion?.termination, .finalized,
                       "Late timeout must not rewrite the recorded termination")
        XCTAssertEqual(run.completion?.transcript, "patient stable")
    }

    func testCancelThenLateResultAndErrorAreIgnored() {
        var run = startedRun()
        XCTAssertNil(run.ingestHypothesis("BP 90", isFinal: false, runID: run.runID, at: t1))
        XCTAssertEqual(run.cancel(runID: run.runID, at: t2)?.termination, .cancelled)

        XCTAssertNil(run.ingestHypothesis("BP 90 over 60", isFinal: true, runID: run.runID, at: t3))
        XCTAssertNil(run.ingestError(reason: "cancelled", runID: run.runID, at: t4))
        XCTAssertEqual(run.completion?.termination, .cancelled)
        XCTAssertEqual(run.completion?.transcript, "BP 90",
                       "Post-cancellation callbacks must not mutate the recorded evidence")
    }

    // MARK: - Run identity: stale callbacks cannot touch a newer run

    func testStaleRunTimeoutCannotCompleteNewRun() {
        var oldRun = startedRun()
        XCTAssertNotNil(oldRun.cancel(runID: oldRun.runID, at: t1))

        var newRun: SpeechFileRunState
        switch SpeechFileRunState.begin(replacing: oldRun, at: t2) {
        case .started(let run): newRun = run
        case .rejectedActiveRun: XCTFail("A finished run must not block a new begin"); return
        }
        XCTAssertNotEqual(newRun.runID, oldRun.runID, "Every run must get a fresh identity")

        // The old run's leaked timer fires with the old identity.
        XCTAssertNil(newRun.fireTimeout(runID: oldRun.runID, at: t3),
                     "A stale run's timeout must be rejected, not complete the new run")
        XCTAssertNil(newRun.completion)
        XCTAssertEqual(newRun.callbackCount, 0)
    }

    func testStaleRunResultCannotContaminateNewRunTranscript() {
        var oldRun = startedRun()
        XCTAssertNotNil(oldRun.cancel(runID: oldRun.runID, at: t1))

        guard case .started(var newRun) = SpeechFileRunState.begin(replacing: oldRun, at: t2) else {
            XCTFail("A finished run must not block a new begin"); return
        }
        XCTAssertNil(newRun.ingestHypothesis("old fixture text", isFinal: true, runID: oldRun.runID, at: t3),
                     "A stale run's result must be rejected")
        XCTAssertEqual(newRun.latestHypothesis, "")
        XCTAssertNil(newRun.completion)

        // The new run's own events still work after the stale rejection.
        XCTAssertNil(newRun.ingestHypothesis("new fixture text", isFinal: false, runID: newRun.runID, at: t4))
        XCTAssertEqual(newRun.latestHypothesis, "new fixture text")
    }

    // MARK: - Overlapping invocation

    func testBeginWhileRunActiveIsRejectedWithoutOverwritingFirst() {
        var active = startedRun()
        XCTAssertNil(active.ingestHypothesis("first run in flight", isFinal: false, runID: active.runID, at: t1))

        switch SpeechFileRunState.begin(replacing: active, at: t2) {
        case .started:
            XCTFail("Overlapping transcribe must be rejected while a run is unfinished")
        case .rejectedActiveRun(let activeRunID):
            XCTAssertEqual(activeRunID, active.runID)
        }
        // The first run is untouched and still completes normally.
        XCTAssertEqual(active.latestHypothesis, "first run in flight")
        let completion = active.ingestHypothesis("first run in flight done", isFinal: true, runID: active.runID, at: t3)
        XCTAssertEqual(completion?.termination, .finalized)
        XCTAssertEqual(completion?.transcript, "first run in flight done")
    }

    // MARK: - Cumulative hypotheses replace, never concatenate

    func testSuccessiveCumulativeHypothesesReplace() {
        var run = startedRun()
        XCTAssertNil(run.ingestHypothesis("massive", isFinal: false, runID: run.runID, at: t1))
        XCTAssertNil(run.ingestHypothesis("massive hemorrhage", isFinal: false, runID: run.runID, at: t2))
        let completion = run.ingestHypothesis("massive hemorrhage controlled", isFinal: true, runID: run.runID, at: t3)

        XCTAssertEqual(completion?.transcript, "massive hemorrhage controlled",
                       "Cumulative partials are one growing hypothesis, not independent utterances")
        XCTAssertEqual(completion?.callbackCount, 3)
        XCTAssertEqual(completion?.firstHypothesisAt, t1, "First-evidence timestamp is the first callback, not the last")
    }

    func testEmptyLateHypothesisDoesNotEraseRetainedText() {
        var run = startedRun()
        XCTAssertNil(run.ingestHypothesis("respirations 22", isFinal: false, runID: run.runID, at: t1))
        XCTAssertNil(run.ingestHypothesis("", isFinal: false, runID: run.runID, at: t2))
        let completion = run.fireTimeout(runID: run.runID, at: t3)
        XCTAssertEqual(completion?.transcript, "respirations 22")
        XCTAssertEqual(completion?.callbackCount, 2)
    }

    // MARK: - Evidence bookkeeping before termination

    func testRunRecordsCallbackEvidenceWhileInFlight() {
        var run = startedRun()
        XCTAssertNil(run.completion)
        XCTAssertNil(run.firstHypothesisAt)
        XCTAssertEqual(run.startedAt, t0)

        XCTAssertNil(run.ingestHypothesis("pulse 118", isFinal: false, runID: run.runID, at: t2))
        XCTAssertEqual(run.callbackCount, 1)
        XCTAssertEqual(run.firstHypothesisAt, t2)
        XCTAssertEqual(run.latestHypothesis, "pulse 118")
        XCTAssertNil(run.completion, "A partial alone must not complete the run")
    }

    // MARK: - Unified callback entry: a callback may carry result, error, or both

    func testCallbackWithResultAndErrorRetainsTextButReportsFailure() throws {
        var run = startedRun()
        XCTAssertNil(run.ingestHypothesis("needle decompression", isFinal: false, runID: run.runID, at: t1))
        let completion = try XCTUnwrap(run.ingestCallback(
            text: "needle decompression left chest", isFinal: true,
            errorReason: "recognition service interrupted", runID: run.runID, at: t2))

        XCTAssertEqual(completion.termination, .failed)
        XCTAssertEqual(completion.transcript, "needle decompression left chest",
                       "Text delivered alongside an error is evidence and must be retained")
        XCTAssertEqual(completion.isComplete, false,
                       "A final flag delivered alongside an error must not claim finalization")
        XCTAssertEqual(completion.failureReason, "recognition service interrupted")
        XCTAssertEqual(completion.firstHypothesisAt, t1)
        XCTAssertEqual(completion.lastHypothesisAt, t2)
        XCTAssertEqual(completion.callbackCount, 2)
    }

    func testCallbackRoutesResultOnlyAndErrorOnlyLikeThePrimitives() throws {
        var finalizedRun = startedRun()
        let finalized = try XCTUnwrap(finalizedRun.ingestCallback(
            text: "patient stable", isFinal: true, errorReason: nil,
            runID: finalizedRun.runID, at: t1))
        XCTAssertEqual(finalized.termination, .finalized)
        XCTAssertEqual(finalized.transcript, "patient stable")
        XCTAssertEqual(finalized.isComplete, true)

        var failedRun = startedRun()
        let failed = try XCTUnwrap(failedRun.ingestCallback(
            text: nil, isFinal: false, errorReason: "no speech detected",
            runID: failedRun.runID, at: t1))
        XCTAssertEqual(failed.termination, .failed)
        XCTAssertEqual(failed.transcript, "")
        XCTAssertEqual(failed.callbackCount, 1, "An error callback is still a recognizer callback")
        XCTAssertNil(failed.firstHypothesisAt, "An error without text is not hypothesis evidence")
    }

    func testCallbackWithNeitherResultNorErrorIsInert() {
        var run = startedRun()
        XCTAssertNil(run.ingestCallback(text: nil, isFinal: false, errorReason: nil,
                                        runID: run.runID, at: t1))
        XCTAssertEqual(run.callbackCount, 0)
        XCTAssertNil(run.completion)
    }

    func testStaleCombinedCallbackCannotTouchNewRun() {
        var oldRun = startedRun()
        XCTAssertNotNil(oldRun.cancel(runID: oldRun.runID, at: t1))
        guard case .started(var newRun) = SpeechFileRunState.begin(replacing: oldRun, at: t2) else {
            XCTFail("A finished run must not block a new begin"); return
        }
        XCTAssertNil(newRun.ingestCallback(
            text: "stale text", isFinal: true, errorReason: "stale error",
            runID: oldRun.runID, at: t3))
        XCTAssertEqual(newRun.latestHypothesis, "")
        XCTAssertEqual(newRun.callbackCount, 0)
        XCTAssertNil(newRun.completion)
    }

    // MARK: - JSON artifact contract (production result type + production encoder)

    private func jsonObject(for result: BenchmarkRunResult) throws -> [String: Any] {
        let data = try BenchmarkRunResult.encoder.encode(result)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTimedOutUnscoredRunEncodesEvidenceAndExplicitUnavailability() throws {
        var run = startedRun()
        XCTAssertNil(run.ingestHypothesis("massive hemorrhage right leg", isFinal: false,
                                          runID: run.runID, at: t1))
        let completion = try XCTUnwrap(run.fireTimeout(runID: run.runID, at: t3))

        let result = BenchmarkRunResult(
            backend: "appleSpeech", mode: "file", fixture: "narration_long.m4a",
            startedAt: "2026-09-08T00:00:00Z", completion: completion, scoring: nil,
            scoringStatus: "unavailable — no bundled reference (narration_long.txt)",
            warnings: ["run terminated by timedOut — retained transcript is partial evidence, not recognizer finalization"],
            availableMemoryBeforeMB: nil, availableMemoryAfterMB: nil)
        let json = try jsonObject(for: result)

        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        XCTAssertEqual(json["termination"] as? String, "timedOut")
        XCTAssertEqual(json["recognizerFinalized"] as? Bool, false)
        XCTAssertEqual(json["hypothesis"] as? String, "massive hemorrhage right leg",
                       "Partial evidence must be persisted even when scoring cannot run")
        XCTAssertEqual(json["callbackCount"] as? Int, 1)
        XCTAssertEqual(json["firstPartialLatencySec"] as? Double, 1)
        XCTAssertEqual(json["lastHypothesisLatencySec"] as? Double, 1)
        XCTAssertEqual(json["wallTimeSec"] as? Double, 3)
        XCTAssertEqual(json["scoringStatus"] as? String,
                       "unavailable — no bundled reference (narration_long.txt)")
        XCTAssertEqual(json["warnings"] as? [String],
                       ["run terminated by timedOut — retained transcript is partial evidence, not recognizer finalization"])
        XCTAssertNil(json["wer"], "No score may be invented for an unscored run")
        XCTAssertNil(json["werPercent"])
        XCTAssertNil(json["keywordRecallPercent"])
        XCTAssertNil(json["extractionPassed"])
    }

    func testNotStartedRunStillProducesArtifact() throws {
        let result = BenchmarkRunResult.notStarted(
            backend: "appleSpeech", mode: "file", fixture: "clip.m4a",
            startedAt: "2026-09-08T00:00:00Z",
            failureReason: "SFSpeechRecognizer unavailable",
            availableMemoryBeforeMB: nil, availableMemoryAfterMB: nil)
        let json = try jsonObject(for: result)

        XCTAssertEqual(json["termination"] as? String, "notStarted")
        XCTAssertEqual(json["recognizerFinalized"] as? Bool, false)
        XCTAssertEqual(json["hypothesis"] as? String, "")
        XCTAssertEqual(json["callbackCount"] as? Int, 0)
        XCTAssertEqual(json["failureReason"] as? String, "SFSpeechRecognizer unavailable")
        XCTAssertEqual(json["scoringStatus"] as? String, "unavailable — transcription did not start")
        XCTAssertNil(json["wer"])
        XCTAssertNil(json["firstPartialLatencySec"])
    }

    // MARK: - Human-readable summary contract (production formatter)

    func testSummaryLineForUnscoredIncompleteRun() throws {
        var run = startedRun()
        XCTAssertNil(run.ingestHypothesis("airway patent breathing labored", isFinal: false,
                                          runID: run.runID, at: t1))
        let completion = try XCTUnwrap(run.ingestError(
            reason: "service interrupted", runID: run.runID, at: t2))

        let result = BenchmarkRunResult(
            backend: "appleSpeech", mode: "file", fixture: "clip.m4a",
            startedAt: "2026-09-08T00:00:00Z", completion: completion, scoring: nil,
            scoringStatus: "unavailable — no bundled reference (clip.txt)",
            warnings: [], availableMemoryBeforeMB: nil, availableMemoryAfterMB: nil)
        let line = BenchmarkSummaryFormatter.line(slug: "clip", result: result)

        XCTAssertTrue(line.hasPrefix("clip: failed INCOMPLETE"),
                      "Incomplete termination must be visible in the summary: \(line)")
        XCTAssertTrue(line.contains("scoring unavailable — no bundled reference (clip.txt)"))
        XCTAssertTrue(line.contains("retained 4 hypothesis words"))
        XCTAssertTrue(line.contains("callbacks 2"))
        XCTAssertTrue(line.contains("reason: service interrupted"))
        XCTAssertFalse(line.contains("WER"), "No WER may be shown when scoring is unavailable")
    }

    func testSummaryLineForFinalizedRunMarksTerminationWithoutIncompleteFlag() throws {
        var run = startedRun()
        let completion = try XCTUnwrap(run.ingestHypothesis(
            "patient stable", isFinal: true, runID: run.runID, at: t2))

        let result = BenchmarkRunResult(
            backend: "appleSpeech", mode: "file", fixture: "clip.m4a",
            startedAt: "2026-09-08T00:00:00Z", completion: completion, scoring: nil,
            scoringStatus: "unavailable — no bundled reference (clip.txt)",
            warnings: [], availableMemoryBeforeMB: nil, availableMemoryAfterMB: nil)
        let line = BenchmarkSummaryFormatter.line(slug: "clip", result: result)

        XCTAssertTrue(line.hasPrefix("clip: finalized"), "Termination kind must lead the line: \(line)")
        XCTAssertFalse(line.contains("INCOMPLETE"),
                       "Recognizer finalization is not flagged incomplete — coverage caveats live in the summary header")
        XCTAssertTrue(line.contains("callbacks 1"))
    }
}
