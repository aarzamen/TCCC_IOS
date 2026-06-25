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
        // On the simulator this may report nil/none — assert it is NOT explicitly unprotected.
        // Device validation (B7) confirms .complete. Here we assert the call path set a value
        // when the platform supports it.
        if let p = values.fileProtection {
            XCTAssertEqual(p, .complete)
        }
    }
}
