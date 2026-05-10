import Foundation

/// Resolves the on-disk location of the Granite Speech model bundle.
///
/// Three sources, tried in priority order per v3 spec §2:
///
/// 1. **Bookmark** — operator-selected Files.app folder in user-managed
///    iCloud Drive or "On My iPhone" storage. Survives app reinstalls
///    when the model files live outside the sandbox.
/// 2. **Bundle resource** — `Bundle.main.url(forResource:withExtension:)`,
///    for future MDM-deployed builds with weights embedded.
/// 3. **HF cache** — populated by `MLXBackend.prefetch()` (the existing
///    no-RECORD-download policy in TCCC_IOS/Intelligence/MLXBackend.swift).
///    Looked up via an injected closure so this package doesn't depend
///    on the app target's Hugging Face cache layout.
///
/// First match wins. If none resolve, throws `.modelNotProvided` and
/// the UI surfaces the "Re-select model folder" banner per v3 §G1.
public struct GraniteSpeechModelResolver: Sendable {
    public enum Source: String, Sendable, Equatable {
        case bookmark
        case bundle
        case hfCache
    }

    public struct Resolved: Sendable, Equatable {
        public let url: URL
        public let source: Source
        /// True only when the URL came from the bookmark store and the
        /// caller must call `startAccessingSecurityScopedResource()`
        /// before reading from it. Bundle and HF-cache URLs live in
        /// app-readable paths and need no scope dance.
        public let needsScopeActivation: Bool

        public init(url: URL, source: Source, needsScopeActivation: Bool) {
            self.url = url
            self.source = source
            self.needsScopeActivation = needsScopeActivation
        }
    }

    public let modelID: String
    public let bookmarkStore: GraniteSpeechBookmarkStore
    public let bundleResourceCheck: @Sendable () -> URL?
    public let hfCacheLookup: @Sendable (_ modelID: String) -> URL?

    /// Default model ID for Sprint 1. v3 §2 locks this to the 5-bit
    /// quantization until the Swift loader's quantization handling has
    /// been verified for other variants.
    public static let defaultModelID = "mlx-community/granite-4.0-1b-speech-5bit"

    /// Default bundle-resource probe — looks for a folder whose name
    /// matches the model's local cache directory convention.
    public static let defaultBundleResourceCheck: @Sendable () -> URL? = {
        Bundle.main.url(forResource: "granite-4.0-1b-speech-5bit", withExtension: nil)
    }

    /// Default HF cache lookup is a no-op so the package stays free of
    /// app-target dependencies. The app target injects a real closure
    /// that calls `HFHubCache.directory(for:)` from `MLXBackend.swift`.
    public static let defaultHFCacheLookup: @Sendable (String) -> URL? = { _ in nil }

    public init(
        modelID: String = Self.defaultModelID,
        bookmarkStore: GraniteSpeechBookmarkStore = GraniteSpeechBookmarkStore(),
        bundleResourceCheck: @escaping @Sendable () -> URL? = Self.defaultBundleResourceCheck,
        hfCacheLookup: @escaping @Sendable (String) -> URL? = Self.defaultHFCacheLookup
    ) {
        self.modelID = modelID
        self.bookmarkStore = bookmarkStore
        self.bundleResourceCheck = bundleResourceCheck
        self.hfCacheLookup = hfCacheLookup
    }

    /// Try each source in order. The async signature gives flexibility
    /// for future cache-prefetch operations; the work in this version
    /// is synchronous.
    public func resolve() async throws -> Resolved {
        if let bookmarkResolved = try? bookmarkStore.resolve() {
            return Resolved(
                url: bookmarkResolved.0,
                source: .bookmark,
                needsScopeActivation: true
            )
        }
        if let bundleURL = bundleResourceCheck() {
            return Resolved(
                url: bundleURL,
                source: .bundle,
                needsScopeActivation: false
            )
        }
        if let cacheURL = hfCacheLookup(modelID) {
            return Resolved(
                url: cacheURL,
                source: .hfCache,
                needsScopeActivation: false
            )
        }
        throw GraniteSpeechResolverError.modelNotProvided(modelID: modelID)
    }
}

public enum GraniteSpeechResolverError: Error, Sendable, Equatable {
    /// All three resolver sources missed. Operator must select a model
    /// folder in Settings (or pre-fetch via Settings download) before
    /// Granite Speech becomes operational.
    case modelNotProvided(modelID: String)

    public var errorDescription: String? {
        switch self {
        case .modelNotProvided(let id):
            return "Granite Speech model '\(id)' not found in any resolver source."
        }
    }
}
