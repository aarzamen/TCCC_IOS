import XCTest
@testable import TCCC_IOS

final class YapLabSessionTests: XCTestCase {
    func testResultKeepsRawTextAndExactPrompts() throws {
        var session = YapLabSession()
        let raw = YapTranscript(backend: .apple, text: "no definite timing stated", status: "Completed")
        session.transcripts.append(raw)
        session.results.append(YapResult(transcriptID: raw.id, backend: .qwen,
            systemPrompt: "preserve uncertainty", taskPrompt: "summarize", text: "Timing unknown."))
        let roundTrip = try JSONDecoder().decode(YapLabSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(roundTrip, session)
        XCTAssertEqual(roundTrip.transcripts[0].text, "no definite timing stated")
        XCTAssertEqual(roundTrip.results[0].transcriptID, raw.id)
        XCTAssertEqual(roundTrip.results[0].systemPrompt, "preserve uncertainty")
    }
    func testPromptPreservesSourceVerbatim() {
        let source = "  uncertain\nNo follow-up supplied.  "
        let prompt = YapPreset.prompt(task: "Review", transcript: source)
        XCTAssertTrue(prompt.contains("<transcript>\n" + source + "\n</transcript>"))
        XCTAssertTrue(prompt.contains("TASK\nReview"))
    }
    func testCancellationRejectsLateCompletionAndPreviousRun() {
        var gate = YapRunGate()
        let first = gate.begin()
        XCTAssertTrue(gate.accepts(first))
        gate.cancel()
        XCTAssertFalse(gate.accepts(first))
        let second = gate.begin()
        XCTAssertFalse(gate.accepts(first))
        XCTAssertTrue(gate.accepts(second))
    }
    func testSessionsDoNotShareTranscriptOrPromptEdits() {
        var first = YapLabSession()
        let second = YapLabSession()
        first.systemPrompt = "Changed"
        first.transcripts.append(YapTranscript(backend: .granite, text: "synthetic source", status: "Incomplete"))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(second.transcripts.isEmpty)
        XCTAssertEqual(second.systemPrompt, YapPreset.clean.system)
    }
    func testFileSupportDoesNotImplySilentFallback() {
        XCTAssertFalse(YapASR.parakeet.supportsFile)
        XCTAssertTrue(YapASR.apple.supportsFile)
        XCTAssertTrue(YapASR.granite.supportsFile)
    }
    func testAudioPathRejectsDirectoryTraversal() {
        let store = YapLabStore(root: URL(fileURLWithPath: "/tmp/yap-synthetic"))
        XCTAssertThrowsError(try store.audioURL("../clinical.json"))
        XCTAssertThrowsError(try store.audioURL("/tmp/other.m4a"))
        XCTAssertEqual(try store.audioURL("clip.m4a").lastPathComponent, "clip.m4a")
    }

    func testDamagedSessionDoesNotHideHealthySessionsOrDeleteEvidence() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = YapLabStore(root: root)
        let healthy = YapLabSession()
        try store.save(healthy)
        let damagedURL = root.appendingPathComponent("damaged.json")
        let damaged = Data("{\"transcripts\":".utf8)
        try damaged.write(to: damagedURL)
        XCTAssertEqual(try store.list().map(\.id), [healthy.id])
        XCTAssertEqual(try store.inventory().unreadableCount, 1)
        XCTAssertEqual(try Data(contentsOf: damagedURL), damaged)
    }

    func testTranscriptFromPreviousVersionDecodesWithoutFailureReason() throws {
        let original = YapTranscript(backend: .apple, text: "original evidence", status: "Incomplete")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "failureReason")
        let restored = try JSONDecoder().decode(YapTranscript.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.text, original.text)
        XCTAssertNil(restored.failureReason)
    }

    func testMismatchedSessionIdentityIsRetainedButNotOfferedAsReopenable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = YapLabStore(root: root)
        try store.prepare()
        let path = root.appendingPathComponent("wrong-id.json")
        let data = try JSONEncoder().encode(YapLabSession())
        try data.write(to: path)
        let inventory = try store.inventory()
        XCTAssertTrue(inventory.sessions.isEmpty)
        XCTAssertEqual(inventory.unreadableCount, 1)
        XCTAssertEqual(try Data(contentsOf: path), data)
    }
}
