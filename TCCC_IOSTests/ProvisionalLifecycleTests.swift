import XCTest
@testable import TCCC_IOS

@MainActor
final class ProvisionalLifecycleTests: XCTestCase {
    func testReplaceSwapsLineInPlaceNotAppend() async {
        let s = AppState()
        s.commitProvisional("TQ applied high end")
        s.applyFinalEcho("TQ applied high and tight")
        XCTAssertEqual(s.transcript.map(\.text), ["TQ applied high and tight"])
    }

    func testTimeoutSettlePromotesProvisionalAsIs() async {
        let s = AppState()
        s.commitProvisional("tourniquet on left leg")
        s.promoteProvisional()   // simulate the settle-timer firing
        XCTAssertEqual(s.transcript.map(\.text), ["tourniquet on left leg"])
        let hasP = await s.engine.hasProvisional
        XCTAssertFalse(hasP)
    }

    // Finding #9/#13: a legitimate restate keeps its anchor words.
    func testRestateKeepsAnchorWords() async {
        let s = AppState()
        s.commitProvisional("Tourniquet applied")
        s.promoteProvisional()
        s.commitProvisional("Tourniquet applied high and tight time 0930")
        s.promoteProvisional()
        XCTAssertEqual(s.transcript.map(\.text),
            ["Tourniquet applied", "Tourniquet applied high and tight time 0930"])
    }

    // Finding #14: two identical back-to-back utterances both survive.
    func testTwoIdenticalBackToBackBothSurvive() async {
        let s = AppState()
        s.commitProvisional("bilateral breath sounds")
        s.promoteProvisional()
        s.commitProvisional("bilateral breath sounds")
        s.promoteProvisional()
        XCTAssertEqual(s.transcript.count, 2)
    }
}
