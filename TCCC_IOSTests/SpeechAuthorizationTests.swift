import XCTest
import Speech
@testable import TCCC_IOS

@MainActor
final class SpeechAuthorizationTests: XCTestCase {
    func testBackgroundPermissionCallbackReturnsToMainActorWithoutCrashing() async {
        let result = await SpeechAuthorization.request(current: .notDetermined) { callback in
            DispatchQueue.global().async { callback(.authorized) }
        }
        XCTAssertEqual(result, .authorized)
        MainActor.assertIsolated()
    }

    func testRepeatedSystemCallbackCompletesOnlyOnce() async {
        let result = await SpeechAuthorization.request(current: .notDetermined) { callback in
            DispatchQueue.global().async {
                callback(.denied)
                callback(.authorized)
            }
        }
        XCTAssertEqual(result, .denied)
    }

    func testDeterminedPermissionDoesNotPromptAgain() async {
        for current in [SFSpeechRecognizerAuthorizationStatus.authorized, .denied, .restricted] {
            let result = await SpeechAuthorization.request(current: current) { _ in
                XCTFail("A determined permission must not ask again")
            }
            XCTAssertEqual(result, current)
        }
    }
}
