import XCTest
@testable import TCCC_IOS

@MainActor
final class PartialCommitGateTests: XCTestCase {
    func testCommitsScheduledTextWhenLatestPartialStillHasItAsStablePrefix() {
        let scheduled = "Massive hemorrhage first I have bright red pulsing blood"
        let latest = "Massive hemorrhage first I have bright red pulsing blood from the left thigh"
        XCTAssertEqual(
            PartialCommitGate.committableText(scheduled: scheduled, latest: latest),
            scheduled
        )
    }

    func testDoesNotCommitWhenRecognizerRevisesTheScheduledPrefix() {
        XCTAssertNil(
            PartialCommitGate.committableText(
                scheduled: "Trepanation his breathing is a little fast",
                latest: "Respiration his breathing is a little fast respirations are 22"
            )
        )
    }
}
