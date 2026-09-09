import XCTest
@testable import TCCC_IOS

@MainActor
final class YapLabEvidenceTests: XCTestCase {
    func testCancelledFileCompletionRetainsPartialEvidenceInItsOwnRow() {
        let model = YapLabModel()
        let raw = YapTranscript(backend: .apple, audioFilename: "source.m4a", text: "", status: "Transcribing file")
        model.session.transcripts = [raw]
        let completion = SpeechFileRunState.Completion(
            termination: .cancelled, transcript: "retained partial words", isComplete: false,
            failureReason: "Cancelled", callbackCount: 1, startedAt: .distantPast,
            firstHypothesisAt: nil, lastHypothesisAt: nil, finishedAt: .distantPast)
        model.retainFileEvidence(completion, transcriptID: raw.id, sessionID: model.session.id)
        XCTAssertEqual(model.session.transcripts[0].text, "retained partial words")
        XCTAssertEqual(model.session.transcripts[0].status, "Cancelled / incomplete")
        model.session.transcripts[0].text = "Current session evidence"
        model.retainFileEvidence(completion, transcriptID: raw.id, sessionID: UUID())
        XCTAssertEqual(model.session.transcripts[0].text, "Current session evidence")
        XCTAssertEqual(model.session.transcripts.count, 1)
    }

    func testImportedSourceWinsUntilAnOlderTranscriptIsExplicitlySelected() {
        let model = YapLabModel()
        let old = YapTranscript(backend: .apple, audioFilename: "old.m4a", text: "old source", status: "Completed")
        model.session.transcripts = [old]
        model.selectedTranscriptID = old.id
        model.session.audioFilename = "new-import.m4a"
        model.selectCurrentAudioSource()
        XCTAssertNil(model.selectedTranscriptID)
        XCTAssertNil(model.transcript, "An older raw row must not appear selected for newly imported audio")
        XCTAssertEqual(model.sourceAudioFilename, "new-import.m4a")
        model.selectedTranscriptID = old.id
        XCTAssertEqual(model.sourceAudioFilename, "old.m4a")
    }

    func testReopenedSourceSelectionMatchesLatestImportedAudio() {
        let model = YapLabModel()
        let current = YapTranscript(backend: .apple, audioFilename: "current.m4a", text: "current", status: "Completed")
        let oldComparison = YapTranscript(backend: .granite, audioFilename: "old.m4a", text: "old", status: "Completed")
        model.session.audioFilename = "current.m4a"
        model.session.transcripts = [current, oldComparison]
        model.selectCurrentAudioSource()
        XCTAssertEqual(model.selectedTranscriptID, current.id)
        XCTAssertEqual(model.sourceAudioFilename, "current.m4a")
    }
}
