import Foundation

/// Persistent security-scoped bookmark for the Granite Speech model
/// folder, lifted from a `UIDocumentPickerViewController` selection in
/// the operator's iCloud Drive or "On My iPhone" storage.
///
/// On iOS, picker-derived URLs are implicitly security-scoped — the
/// caller is responsible for `startAccessingSecurityScopedResource`
/// after resolving and `stopAccessingSecurityScopedResource` when
/// done. This store handles the bookmark lifecycle (save / resolve /
/// stale-detect / recreate) but **does not** activate the scope for
/// the caller. Scope activation is `GraniteSpeechRuntime.prime()`'s
/// job, held for the lifetime of the loaded model.
///
/// Persistence: `UserDefaults` under
/// `tccc.graniteSpeech.modelBookmarkV1` by default. UserDefaults
/// survives app relaunch and most reinstalls, but a hard sandbox
/// wipe (e.g. a SideStore "delete + reinstall" cycle) clears it. The
/// model files themselves survive in user-managed Files.app storage
/// outside the sandbox; if the bookmark is gone the operator
/// re-picks the same folder once and the store is rehydrated.
public struct GraniteSpeechBookmarkStore: Sendable {
    public static let defaultKey = "tccc.graniteSpeech.modelBookmarkV1"

    public let key: String
    private let defaultsProvider: @Sendable () -> UserDefaults

    public init(
        key: String = Self.defaultKey,
        defaults: @autoclosure @escaping @Sendable () -> UserDefaults = .standard
    ) {
        self.key = key
        self.defaultsProvider = defaults
    }

    /// Persist a security-scoped bookmark for `url`. The caller must
    /// hold an active scope on `url` (typically from the document
    /// picker callback) when invoking this. On iOS the bookmark
    /// options are an empty set — picker URLs carry implicit scope.
    public func save(url: URL) throws {
        let data = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaultsProvider().set(data, forKey: key)
    }

    /// Resolve the persisted bookmark. Returns `(url, isStale)` —
    /// caller is responsible for activating the security scope after
    /// receiving the URL. On stale, the store opportunistically
    /// re-creates the bookmark while a scope handle can be briefly
    /// acquired here, so the next resolve is fresh.
    public func resolve() throws -> (URL, isStale: Bool) {
        let defaults = defaultsProvider()
        guard let data = defaults.data(forKey: key) else {
            throw GraniteSpeechBookmarkError.noBookmarkSaved
        }
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        if isStale, url.startAccessingSecurityScopedResource() {
            defer { url.stopAccessingSecurityScopedResource() }
            if let refreshed = try? url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                defaults.set(refreshed, forKey: key)
            }
        }
        return (url, isStale)
    }

    public func clear() {
        defaultsProvider().removeObject(forKey: key)
    }

    /// Convenience: true if any bookmark data is currently persisted.
    /// Does not validate that the bookmark still resolves.
    public var hasBookmark: Bool {
        defaultsProvider().data(forKey: key) != nil
    }
}

public enum GraniteSpeechBookmarkError: Error, Sendable, Equatable {
    case noBookmarkSaved
}
