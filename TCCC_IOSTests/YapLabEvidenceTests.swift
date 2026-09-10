import XCTest
import Speech
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
        let encoded = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(model.session)) as! [String: Any]
        let rows = encoded["transcripts"] as! [[String: Any]]
        XCTAssertEqual(rows[0]["failureReason"] as? String, "Cancelled")
        XCTAssertTrue(model.shareText.contains("Cancelled"))
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

    func testUnreadableNeighborDoesNotBlockReopeningHealthySession() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = YapLabStore(root: root)
        var healthy = YapLabSession()
        healthy.title = "Synthetic saved comparison"
        try store.save(healthy)
        try Data("truncated json".utf8).write(to: root.appendingPathComponent("broken.json"))
        let model = YapLabModel(store: store)
        let initialID = model.session.id
        model.refresh()
        XCTAssertEqual(model.saved.map(\.id), [healthy.id])
        XCTAssertEqual(model.unreadableSessionCount, 1)
        model.reopen(healthy.id)
        XCTAssertEqual(model.session.id, healthy.id)
        XCTAssertNotEqual(model.session.id, initialID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("broken.json").path))
    }

    func testSavedFailureReasonSurvivesReopenAndShare() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = YapLabStore(root: root)
        let model = YapLabModel(store: store)
        let raw = YapTranscript(backend: .apple, text: "retained words", status: "Transcribing file")
        model.session.transcripts = [raw]
        let completion = SpeechFileRunState.Completion(
            termination: .cancelled, transcript: "retained words", isComplete: false,
            failureReason: "Synthetic interruption detail", callbackCount: 1, startedAt: .distantPast,
            firstHypothesisAt: nil, lastHypothesisAt: nil, finishedAt: .distantPast)
        model.retainFileEvidence(completion, transcriptID: raw.id, sessionID: model.session.id)
        model.save()
        let recovered = YapLabModel(store: store)
        recovered.reopen(model.session.id)
        XCTAssertTrue(recovered.shareText.contains("Synthetic interruption detail"))
        XCTAssertEqual(recovered.transcript?.text, "retained words")
    }

    func testPermissionRecoveryMatchesSelectedRecognizerAndRestriction() {
        let model = YapLabModel()
        model.microphoneDenied = false
        model.speechPermission = .denied
        XCTAssertTrue(model.canOpenPermissionSettings)
        XCTAssertTrue(model.permissionGuidance?.contains("Speech Recognition") == true)
        model.session.asr = .granite
        XCTAssertFalse(model.canOpenPermissionSettings)
        XCTAssertNil(model.permissionGuidance, "Granite does not need Apple Speech permission")
        model.session.asr = .apple
        model.speechPermission = .restricted
        XCTAssertFalse(model.canOpenPermissionSettings, "Settings cannot remove a system restriction")
        XCTAssertTrue(model.permissionGuidance?.contains("restricted") == true)
        model.microphoneDenied = true
        XCTAssertTrue(model.canOpenPermissionSettings)
        XCTAssertTrue(model.permissionGuidance?.contains("audio import remains available") == true)
    }
}
