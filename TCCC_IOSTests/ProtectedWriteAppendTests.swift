// TCCC_IOSTests/ProtectedWriteAppendTests.swift
import XCTest
@testable import TCCC_IOS

final class ProtectedWriteAppendTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pwtest-\(UUID().uuidString)", isDirectory: true)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testAppendLineCreatesDirAndFileAndRoundTrips() throws {
        let file = dir.appendingPathComponent("nested/events.jsonl")
        try ProtectedWrite.appendLine("{\"a\":1}", to: file)
        try ProtectedWrite.appendLine("{\"b\":2}", to: file)
        let contents = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(contents, "{\"a\":1}\n{\"b\":2}\n")
    }

    func testAppendedFileHasCompleteProtection() throws {
        let file = dir.appendingPathComponent("events.jsonl")
        try ProtectedWrite.appendLine("x", to: file)
        let values = try file.resourceValues(forKeys: [.fileProtectionKey])
#if targetEnvironment(simulator)
        // The macOS-backed simulator can return a default URL protection value
        // while omitting the actual file-protection attribute. It cannot prove
        // iOS encryption behavior; run the strict assertion on physical iOS.
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        if attributes[.protectionKey] == nil {
            throw XCTSkip("Simulator does not expose the file protection class; requires physical iOS")
        }
#endif
        XCTAssertEqual(try XCTUnwrap(values.fileProtection), .complete)
    }
}
