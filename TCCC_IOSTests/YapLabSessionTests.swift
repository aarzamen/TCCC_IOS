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
}
