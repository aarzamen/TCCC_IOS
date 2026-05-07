import XCTest
@testable import TCCC_IOS

@MainActor
final class LLMBackendPolicyTests: XCTestCase {
    func testAppleFoundationModelsIsTheRuntimeDefault() {
        let state = AppState()

        XCTAssertEqual(state.llmBackend, .appleFoundation)
    }

    func testGraniteTextBackendIsExplicitAltOnly() {
        let state = AppState()

        XCTAssertTrue(AppState.LLMBackend.allCases.contains(.graniteText))
        XCTAssertEqual(state.llmBackend, .appleFoundation)

        state.llmBackend = .graniteText

        XCTAssertEqual(state.currentBackend.displayName, "IBM Granite 4.0 H 1B Base")
        XCTAssertEqual(GraniteTextLLMBackend.modelId, "mlx-community/granite-4.0-h-1b-base-4bit")
    }

    func testMLXGenerateRefusesMissingWeightsBeforeLoaderCanDownload() async {
        let backend = MLXBackend(
            displayName: "Missing Test Model",
            modelId: "codex-test/missing-model-\(UUID().uuidString)"
        )

        let availability = await backend.availability
        XCTAssertEqual(availability, .modelNotProvided)

        do {
            _ = try await backend.generate(instructions: "test", prompt: "hello")
            XCTFail("MLXBackend.generate must refuse missing weights before model loading")
        } catch BackendError.modelNotProvided(let name) {
            XCTAssertEqual(name, "Missing Test Model")
        } catch {
            XCTFail("Expected modelNotProvided, got \(error)")
        }
    }

    func testModelNotProvidedMessageDoesNotInviteImplicitDownload() {
        let message = BackendAvailability.modelNotProvided.message(
            for: "Liquid LFM2.5 1.2B"
        )

        XCTAssertTrue(message.contains("Liquid LFM2.5 1.2B"))
        XCTAssertTrue(message.contains("Download"))
        XCTAssertFalse(message.lowercased().contains("try again"))
    }
}
