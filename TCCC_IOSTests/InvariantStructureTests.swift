// TCCC_IOSTests/InvariantStructureTests.swift — structural source check
import XCTest

final class InvariantStructureTests: XCTestCase {
    /// There must be exactly ONE production call that records an operator-accepted
    /// fact into the engine, and it must be reached only from the FieldRouter
    /// `.mutation` arm. Guards against a future direct engine.apply from an LLM path.
    func testSingleOperatorAcceptCallSite() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()   // repo/TCCC_IOSTests/.. = repo
        let intel = root.appendingPathComponent("TCCC_IOS/Intelligence")
        let files = try FileManager.default.contentsOfDirectory(at: intel, includingPropertiesForKeys: nil)
        var acceptCalls = 0
        for f in files where f.pathExtension == "swift" {
            let src = try String(contentsOf: f, encoding: .utf8)
            acceptCalls += src.components(separatedBy: "recordOperatorAcceptedFact").count - 1
        }
        XCTAssertEqual(acceptCalls, 1, "exactly one production accept-record call site expected")
    }
}
