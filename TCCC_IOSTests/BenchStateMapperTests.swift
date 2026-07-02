import XCTest
import TCCCExtractor
@testable import TCCC_IOS

final class BenchStateMapperTests: XCTestCase {
    func testMapperReadsVitalsFromEngine() async {
        let engine = PatientStateEngine.standard()
        await engine.processTranscript("BP is 88 over 60. Heart rate 135. Respiratory rate 32.", timestamp: Date())
        let snapshot = await engine.snapshot()
        let actual = BenchStateMapper.map(snapshot["PATIENT_1"])
        XCTAssertEqual(actual["bp"], "88/60")
        XCTAssertEqual(actual["hr"], "135")
        XCTAssertEqual(actual["rr"], "32")
    }

    func testMapperEmptyStateIsEmpty() {
        XCTAssertTrue(BenchStateMapper.map(nil).isEmpty)
    }
}
