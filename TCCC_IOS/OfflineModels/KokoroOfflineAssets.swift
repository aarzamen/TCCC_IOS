import Foundation
import FluidAudio

/// FluidAudio 0.14.4 hard-codes auxiliary resources to its cache even when models
/// are injected. Materialize those files from the verified local package before
/// invoking initialization; never call TtsModels.download from synthesis.
enum KokoroOfflineAssets {
    static func prepareLocalResources() throws -> URL {
        guard let source = OfflineModelAssets.resolve(modelID: OfflineModelAssets.kokoroID) else {
            throw KokoroEngineError.synthesisFailed("Kokoro offline package missing or incomplete. Prepare models on the install Mac.")
        }
        let cache = try TtsModels.cacheDirectoryURL().appendingPathComponent("Models/kokoro")
        if source.standardizedFileURL == cache.standardizedFileURL { return source }
        let fm = FileManager.default
        let entries = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? []
        for file in entries where OfflineModelAssets.fileSize(file) > 0 {
            let relative = String(file.path.dropFirst(source.path.count + 1))
            // Large synthesis models load directly from their durable location.
            if relative.hasPrefix("kokoro_21_") || relative == "asset-manifest.json" { continue }
            let target = cache.appendingPathComponent(relative)
            if OfflineModelAssets.fileSize(target) == OfflineModelAssets.fileSize(file) { continue }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporary = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).preparing")
            try fm.copyItem(at: file, to: temporary)
            do {
                if fm.fileExists(atPath: target.path) {
                    _ = try fm.replaceItemAt(target, withItemAt: temporary)
                } else {
                    try fm.moveItem(at: temporary, to: target)
                }
            } catch {
                try? fm.removeItem(at: temporary)
                throw error
            }
        }
        // SDK's ensure methods return locally because every auxiliary file exists.
        for name in ["vocab_index.json", "us_lexicon_cache.json", "g2p_vocab.json"] {
            guard OfflineModelAssets.json(at: cache.appendingPathComponent(name)) != nil else {
                throw KokoroEngineError.synthesisFailed("Kokoro auxiliary file unavailable: \(name)")
            }
        }
        for voice in TtsConstants.availableVoices {
            guard OfflineModelAssets.json(at: cache.appendingPathComponent("voices/\(voice).json")) != nil else {
                throw KokoroEngineError.synthesisFailed("Kokoro voice unavailable: \(voice)")
            }
        }
        return source
    }
}
