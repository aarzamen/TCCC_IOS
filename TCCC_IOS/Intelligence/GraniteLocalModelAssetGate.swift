import Foundation

enum GraniteLocalModelAssetFailure: Sendable, Equatable, Hashable, CustomStringConvertible {
    case directoryMissing(String)
    case configMissing(String)
    case tokenizerMissing(String)
    case weightsMissing(String)

    var description: String {
        switch self {
        case .directoryMissing(let path):
            return "Model directory is missing: \(path)"
        case .configMissing(let path):
            return "Missing config.json in model directory: \(path)"
        case .tokenizerMissing(let path):
            return "Missing tokenizer.json or tokenizer.model in model directory: \(path)"
        case .weightsMissing(let path):
            return "Missing .safetensors weights in model directory: \(path)"
        }
    }
}

struct GraniteLocalModelAssetReport: Sendable, Equatable {
    let modelDirectory: URL
    let failures: Set<GraniteLocalModelAssetFailure>

    var isUsable: Bool { failures.isEmpty }
}

enum GraniteLocalModelAssetGate {
    static func validate(modelDirectory: URL) -> GraniteLocalModelAssetReport {
        var failures: Set<GraniteLocalModelAssetFailure> = []
        var isDirectory: ObjCBool = false
        let path = modelDirectory.path

        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return GraniteLocalModelAssetReport(
                modelDirectory: modelDirectory,
                failures: [.directoryMissing(path)]
            )
        }

        if !FileManager.default.fileExists(
            atPath: modelDirectory.appendingPathComponent("config.json").path
        ) {
            failures.insert(.configMissing(path))
        }

        let tokenizerCandidates = [
            "tokenizer.json",
            "tokenizer.model"
        ]
        let hasTokenizer = tokenizerCandidates.contains { candidate in
            FileManager.default.fileExists(
                atPath: modelDirectory.appendingPathComponent(candidate).path
            )
        }
        if !hasTokenizer {
            failures.insert(.tokenizerMissing(path))
        }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: modelDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        let hasWeights = entries.contains { url in
            url.lastPathComponent.hasSuffix(".safetensors")
                || url.lastPathComponent.hasSuffix(".safetensors.index.json")
        }
        if !hasWeights {
            failures.insert(.weightsMissing(path))
        }

        return GraniteLocalModelAssetReport(
            modelDirectory: modelDirectory,
            failures: failures
        )
    }

    static func explicitModelDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        guard let path = environment["TCCC_GRANITE_MODEL_DIR"], !path.isEmpty else {
            throw BackendError.modelNotProvided(backend: "IBM Granite 4.0 H 1B Base")
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
