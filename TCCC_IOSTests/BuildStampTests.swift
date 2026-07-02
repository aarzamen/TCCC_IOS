import XCTest
@testable import TCCC_IOS

final class BuildStampTests: XCTestCase {
    func testStampDisplayIsWellFormed() {
        let s = BuildStamp.current
        XCTAssertFalse(s.version.isEmpty)
        XCTAssertTrue(s.display.contains(s.gitSHA))
    }

    func testProductPlistCarriesGitStamp() {
        // The post-build script must have stamped the test-host app bundle.
        let sha = Bundle.main.infoDictionary?["TCCCGitSHA"] as? String
        XCTAssertNotNil(sha, "TCCCGitSHA missing — postBuildScripts stamp did not run")
        XCTAssertNotEqual(sha, "unknown")
    }
}
