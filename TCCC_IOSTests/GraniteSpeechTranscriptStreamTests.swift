import XCTest
@testable import TCCC_IOS

@MainActor
final class GraniteSpeechTranscriptStreamTests: XCTestCase {
    func testGraniteSpeechIsExplicitAlternateASRBackend() {
        XCTAssertEqual(AppState().asrBackend, .appleSpeech)
        XCTAssertTrue(AppState.ASRBackend.allCases.contains(.graniteSpeech))
        XCTAssertEqual(
            AppState.ASRBackend.graniteSpeech.displayName,
            "Granite Speech (research)"
        )
    }

    func testGraniteSpeechStreamReportsUnavailableWithoutStartingNetworkOrAudio() async {
        let stream = GraniteSpeechTranscriptStream()

        do {
            try await stream.authorize()
            XCTFail("Granite Speech should report unavailable until a Swift runtime exists")
        } catch TranscriptStreamError.backendUnavailable(let message) {
            XCTAssertTrue(message.contains("Granite Speech"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await stream.start(audioURL: nil)
            XCTFail("Granite Speech should not start without a Swift runtime")
        } catch TranscriptStreamError.backendUnavailable(let message) {
            XCTAssertTrue(message.contains("Swift runtime"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
