import XCTest
@testable import TCCCExtractor
@testable import TCCCDomain

final class ProvisionalReplaceTests: XCTestCase {
    func testTruncateDropsTailToCount() {
        var log = EncounterLog()
        let seg = { (i: Int) in EncounterEvent.asrSegment(.init(
            id: "s\(i)", patientId: "PATIENT_1", timestampUnix: 0, text: "t\(i)",
            backend: "test", isFinal: true)) }
        log.append(seg(0)); log.append(seg(1)); log.append(seg(2))
        log.truncate(toCount: 1)
        XCTAssertEqual(log.events.map(\.id), ["s0"])
    }

    func testTruncateNoopWhenCountAtOrAboveLength() {
        var log = EncounterLog()
        log.append(.asrSegment(.init(id: "s0", patientId: "P", timestampUnix: 0,
            text: "t", backend: "test", isFinal: true)))
        log.truncate(toCount: 5)
        XCTAssertEqual(log.events.count, 1)
    }
}
