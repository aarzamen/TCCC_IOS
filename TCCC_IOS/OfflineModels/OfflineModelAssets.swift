import Foundation

/// Local-only inventory shared by inference, installation UI and legacy callers.
/// Readiness means complete files, not model quality or a successful runtime load.
enum OfflineModelAssets {
    static let kokoroID = "FluidInference/kokoro-82m-coreml"
    static let parakeetID = "FluidInference/parakeet-realtime-eou-120m-coreml"
    static let modelIDs = [
        "mlx-community/LFM2-1.2B-4bit",
        "mlx-community/Qwen3-1.7B-4bit",
        "mlx-community/granite-4.0-h-1b-base-4bit",
        "mlx-community/granite-4.0-1b-speech-5bit",
        parakeetID, kokoroID
    ]

    static func folderName(_ modelID: String) -> String {
        modelID.replacingOccurrences(of: "/", with: "--")
    }

    static var roots: [URL] {
        let fm = FileManager.default
        return [Bundle.main.resourceURL?.appendingPathComponent("OfflineModels")]
            .compactMap { $0 }
            + [.applicationSupportDirectory, .documentDirectory].compactMap {
                fm.urls(for: $0, in: .userDomainMask).first?.appendingPathComponent("OfflineModels")
            }
    }

    static func resolve(modelID: String) -> URL? {
        resolve(modelID: modelID, roots: roots, legacyCandidates: legacyCandidates(modelID))
    }

    /// Injection seam permits missing/partial/valid fixture checks without real weights.
    static func resolve(modelID: String, roots: [URL], legacyCandidates: [URL]) -> URL? {
        (roots.map { $0.appendingPathComponent(folderName(modelID)) } + legacyCandidates)
            .first { problems(at: $0, modelID: modelID).isEmpty }
    }

    static var parakeetDirectory: URL? { resolve(modelID: parakeetID) }

    static func legacyCandidates(_ modelID: String) -> [URL] {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first
        if modelID == kokoroID {
            return [caches?.appendingPathComponent("fluidaudio/Models/kokoro")].compactMap { $0 }
        }
        if modelID == parakeetID {
            return [support?.appendingPathComponent(
                "FluidAudio/Models/parakeet-eou-streaming/parakeet-realtime-eou-120m-coreml/160ms"
            )].compactMap { $0 }
        }
        var candidates = [
            docs?.appendingPathComponent("huggingface/models/\(modelID)"),
            docs?.appendingPathComponent("models/\(modelID)"),
            docs?.appendingPathComponent(String(modelID.split(separator: "/").last ?? "")),
            caches?.appendingPathComponent("models/\(modelID)")
        ].compactMap { $0 }
        for root in [caches, docs].compactMap({ $0 }) {
            let snapshots = root.appendingPathComponent("huggingface/hub/models--\(folderName(modelID))/snapshots")
            let entries = (try? fm.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)) ?? []
            candidates += entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        return candidates
    }

    static func problems(at directory: URL, modelID: String) -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return ["Model folder missing"] }
        let manifestIssues = manifestProblems(at: directory, modelID: modelID)
        if modelID == kokoroID { return manifestIssues + kokoroProblems(at: directory) }
        if modelID == parakeetID { return manifestIssues + parakeetProblems(at: directory) }
        return manifestIssues + mlxProblems(at: directory)
    }

    /// Packaged resources carry a SHA-256 manifest verified by the build script.
    /// Runtime checks identity and byte counts without rehashing gigabytes per button.
    /// Code signing protects bundled bytes; this check detects missing/truncated imports.
    static func manifestProblems(at directory: URL, modelID: String) -> [String] {
        let manifestURL = directory.appendingPathComponent("asset-manifest.json")
        let exists = FileManager.default.fileExists(atPath: manifestURL.path)
        let packaged = directory.deletingLastPathComponent().lastPathComponent == "OfflineModels"
        guard exists || packaged else { return [] }
        guard let manifest = json(at: manifestURL), manifest["schemaVersion"] as? Int == 1,
              manifest["modelID"] as? String == modelID,
              let files = manifest["files"] as? [[String: Any]], !files.isEmpty else {
            return ["Missing or invalid asset manifest"]
        }
        for file in files {
            guard let path = file["path"] as? String, safeRelativePath(path),
                  let bytes = file["bytes"] as? UInt64, bytes > 0,
                  fileSize(directory.appendingPathComponent(path)) == bytes else {
                return ["Manifest file missing or truncated"]
            }
        }
        return []
    }

    static func mlxProblems(at directory: URL) -> [String] {
        var problems: [String] = []
        for name in ["config.json", "tokenizer_config.json"] {
            if json(at: directory.appendingPathComponent(name)) == nil { problems.append("Missing or invalid \(name)") }
        }
        if json(at: directory.appendingPathComponent("tokenizer.json")) == nil,
           fileSize(directory.appendingPathComponent("tokenizer.model")) == 0 {
            problems.append("Tokenizer missing or invalid")
        }
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let indexURL = directory.appendingPathComponent("model.safetensors.index.json")
        var weights = entries.filter { $0.pathExtension == "safetensors" }
        if FileManager.default.fileExists(atPath: indexURL.path) {
            guard let index = json(at: indexURL), let map = index["weight_map"] as? [String: String], !map.isEmpty,
                  map.values.allSatisfy({ safeRelativePath($0) && $0.hasSuffix(".safetensors") }) else {
                return problems + ["Invalid weight shard index"]
            }
            weights = Set(map.values).map { directory.appendingPathComponent($0) }
        }
        if weights.isEmpty { problems.append("Weights missing") }
        for weight in weights where !validSafetensors(weight) {
            problems.append("Missing or incomplete \(weight.lastPathComponent)")
        }
        return problems
    }

    static func parakeetProblems(at directory: URL) -> [String] {
        var problems: [String] = []
        if json(at: directory.appendingPathComponent("vocab.json")) == nil { problems.append("Vocabulary missing or invalid") }
        for name in ["streaming_encoder.mlmodelc", "decoder.mlmodelc", "joint_decision.mlmodelc"] {
            let root = directory.appendingPathComponent(name)
            // These are the exact three compiled bundles shipped by the pinned SDK.
            if ["coremldata.bin", "model.mil", "weights/weight.bin"].contains(where: {
                fileSize(root.appendingPathComponent($0)) == 0
            }) {
                problems.append("Incomplete \(name)")
            }
        }
        return problems
    }

    static func kokoroProblems(at directory: URL) -> [String] {
        var problems: [String] = []
        for name in ["config.json", "vocab_index.json", "us_lexicon_cache.json", "g2p_vocab.json"] {
            if json(at: directory.appendingPathComponent(name)) == nil { problems.append("Missing or invalid \(name)") }
        }
        for name in ["kokoro_21_5s.mlmodelc", "kokoro_21_15s.mlmodelc", "G2PEncoder.mlmodelc", "G2PDecoder.mlmodelc"] {
            if ["coremldata.bin", "model.mil", "weights/weight.bin"].contains(where: {
                fileSize(directory.appendingPathComponent(name).appendingPathComponent($0)) == 0
            }) { problems.append("Incomplete \(name)") }
        }
        let voices = directory.appendingPathComponent("voices")
        let entries = (try? FileManager.default.contentsOfDirectory(at: voices, includingPropertiesForKeys: nil)) ?? []
        if entries.filter({ $0.pathExtension == "json" && json(at: $0) != nil }).count < 54 {
            problems.append("Full 54-voice set missing or incomplete")
        }
        return problems
    }

    static func safeRelativePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    static func json(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func fileSize(_ url: URL) -> UInt64 {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return 0 }
        return UInt64(max(0, values?.fileSize ?? 0))
    }

    /// Read only the header, verifying every declared tensor fits in the file.
    /// Rejects Git LFS pointers, empty placeholders and truncated shard payloads.
    static func validSafetensors(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 8), prefix.count == 8 else { return false }
        let length = prefix.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
        guard length > 1, length < 100_000_000, fileSize(url) > 8 + length,
              let header = try? handle.read(upToCount: Int(length)), header.count == Int(length),
              let objects = (try? JSONSerialization.jsonObject(with: header)) as? [String: Any] else { return false }
        let tensors = objects.filter { $0.key != "__metadata__" }
        guard !tensors.isEmpty else { return false }
        let payload = fileSize(url) - 8 - length
        return tensors.values.allSatisfy {
            guard let tensor = $0 as? [String: Any], let offsets = tensor["data_offsets"] as? [UInt64],
                  offsets.count == 2 else { return false }
            return offsets[0] <= offsets[1] && offsets[1] <= payload
        }
    }
}
