import Foundation
import MLX
import MLXAudioSTT
import MLXNN
import Tokenizers

/// URL-direct loader for `GraniteSpeechModel`, mirroring the body of
/// `MLXAudioSTT.GraniteSpeechModel.fromPretrained(_:cache:)` (Sprint
/// 1 v3 §G2 task 1).
///
/// `fromPretrained` internally calls
/// `ModelUtils.resolveOrDownloadModel(repoID:requiredExtension:cache:)`
/// which mangles the path to `<cacheDirectory>/mlx-audio/<owner>_<repo>/`
/// — meaning the operator would have to drop the model files in that
/// nested layout for the resolver to find them. This loader bypasses
/// that mangling and accepts the model directory URL directly, so
/// the operator's Files.app folder can be a flat directory of
/// `config.json + *.safetensors + tokenizer.json` files.
///
/// All callees are public on the upstream packages (verified against
/// pinned SHA `fcbd04daa1bfebe881932f630af2ba6ce9af3274`):
/// `GraniteSpeechModelConfig` (Codable),
/// `GraniteSpeechModel.init(_:)`,
/// `GraniteSpeechModel.tokenizer` (public var),
/// `GraniteSpeechModel.sanitize(weights:)` (public static),
/// `MLX.loadArrays(url:)`,
/// `MLXNN.quantize(model:perLayer:)`,
/// `Tokenizers.AutoTokenizer.from(modelFolder:)`.
public enum GraniteSpeechModelLoader {

    public enum LoaderError: Error, LocalizedError, Sendable {
        case missingConfig(URL)
        case missingSafetensors(URL)
        case configDecodeFailed(underlying: String)
        case tokenizerLoadFailed(underlying: String)
        case weightLoadFailed(underlying: String)

        public var errorDescription: String? {
            switch self {
            case .missingConfig(let url):
                return "Missing config.json under \(url.lastPathComponent)."
            case .missingSafetensors(let url):
                return "No *.safetensors files under \(url.lastPathComponent)."
            case .configDecodeFailed(let m):
                return "Failed to decode config.json: \(m)"
            case .tokenizerLoadFailed(let m):
                return "Failed to load tokenizer: \(m)"
            case .weightLoadFailed(let m):
                return "Failed to load weights: \(m)"
            }
        }
    }

    /// Load a `GraniteSpeechModel` from a directory containing
    /// `config.json`, one or more `*.safetensors`, and the tokenizer
    /// files. Caller must hold security scope on `modelDir` for the
    /// duration of this call.
    public static func loadFromModelDirectory(_ modelDir: URL) async throws -> GraniteSpeechModel {
        let fileManager = FileManager.default

        let configURL = modelDir.appendingPathComponent("config.json")
        guard fileManager.fileExists(atPath: configURL.path) else {
            throw LoaderError.missingConfig(modelDir)
        }

        let configData: Data
        let config: GraniteSpeechModelConfig
        do {
            configData = try Data(contentsOf: configURL)
            config = try JSONDecoder().decode(GraniteSpeechModelConfig.self, from: configData)
        } catch {
            throw LoaderError.configDecodeFailed(underlying: error.localizedDescription)
        }

        let model = GraniteSpeechModel(config)

        do {
            model.tokenizer = try await AutoTokenizer.from(modelFolder: modelDir)
        } catch {
            throw LoaderError.tokenizerLoadFailed(underlying: error.localizedDescription)
        }

        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: modelDir, includingPropertiesForKeys: nil
            )
        } catch {
            throw LoaderError.weightLoadFailed(underlying: error.localizedDescription)
        }
        let safetensorFiles = entries.filter { $0.pathExtension == "safetensors" }
        guard !safetensorFiles.isEmpty else {
            throw LoaderError.missingSafetensors(modelDir)
        }

        var weights: [String: MLXArray] = [:]
        do {
            for file in safetensorFiles {
                let fileWeights = try MLX.loadArrays(url: file)
                weights.merge(fileWeights) { _, new in new }
            }
        } catch {
            throw LoaderError.weightLoadFailed(underlying: error.localizedDescription)
        }

        let sanitizedWeights = GraniteSpeechModel.sanitize(weights: weights)

        if let perLayerQuantization = config.perLayerQuantization {
            quantize(model: model) { path, _ in
                if sanitizedWeights["\(path).scales"] != nil {
                    return perLayerQuantization.quantization(layer: path)?.asTuple
                }
                return nil
            }
        }

        do {
            try model.update(
                parameters: ModuleParameters.unflattened(sanitizedWeights),
                verify: .all
            )
        } catch {
            throw LoaderError.weightLoadFailed(underlying: error.localizedDescription)
        }

        eval(model)

        return model
    }
}
