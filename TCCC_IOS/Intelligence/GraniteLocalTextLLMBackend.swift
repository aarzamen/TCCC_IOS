import Foundation
import TCCCLLM

actor GraniteLocalTextLLMBackend: TCCCLLMBackend {
    nonisolated let displayName = "IBM Granite 4.0 H 1B Base Local"

    private let modelId: String
    private let modelDirectory: URL

    init(
        modelId: String = GraniteTextLLMBackend.modelId,
        modelDirectory: URL
    ) {
        self.modelId = modelId
        self.modelDirectory = modelDirectory
    }

    var availability: BackendAvailability {
        get async {
            GraniteLocalModelAssetGate.validate(
                modelDirectory: modelDirectory
            ).isUsable ? .available : .modelNotProvided
        }
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        let report = GraniteLocalModelAssetGate.validate(modelDirectory: modelDirectory)
        guard report.isUsable else {
            throw BackendError.modelNotProvided(backend: displayName)
        }

        let model = MLXLanguageModel(modelId: modelId, directory: modelDirectory)
        let session = LanguageModelSession(model: model, instructions: instructions)
        var options = GenerationOptions()
        options.maximumResponseTokens = 768

        do {
            let response = try await session.respond(to: prompt, options: options)
            return response.content
        } catch {
            throw BackendError.generationFailed(
                "\(displayName): \(error.localizedDescription)"
            )
        }
    }
}
