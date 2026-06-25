import XCTest
@testable import TCCC_IOS

@MainActor
final class LifecycleAffordanceTests: XCTestCase {
    func testWipeAndNewCasualtyHaveDistinctConfirmationCopy() {
        // Distinct headlines so a gloved operator can never confuse them.
        XCTAssertNotEqual(ConfirmationAction.wipe.headline, ConfirmationAction.newPatient.headline)
        XCTAssertTrue(ConfirmationAction.wipe.headline.uppercased().contains("WIPE"))
        XCTAssertFalse(ConfirmationAction.newPatient.headline.uppercased().contains("WIPE"))
    }
}
