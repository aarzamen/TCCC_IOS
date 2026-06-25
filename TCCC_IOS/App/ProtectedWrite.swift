import Foundation

/// Helpers that funnel every casualty-identifying disk write through
/// `NSFileProtectionComplete` (a.k.a. `URLFileProtection.complete`).
///
/// CLAUDE.md hard constraint #3: AES-256 at rest via Apple Data Protection.
/// `Data.write(to:options:)` with `.atomic` alone leaves the file readable
/// when the device is locked — that violates the contract. Every casualty
/// artifact (encounter JSON, vitals CSV, transcript, .wav audio capture,
/// future DD-1380 PDF) must go through one of these helpers.
enum ProtectedWrite {

    /// Atomic + complete file protection. Use for any casualty-identifying
    /// artifact written in a single shot.
    static func data(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Create a placeholder file with complete protection so subsequent
    /// streamed writes (`AVAudioFile`, `FileHandle.write`) inherit the
    /// protection class. The protection attribute is set on creation; the
    /// `setResourceValue` call is a belt-and-braces idempotent re-mark in
    /// case the file already existed.
    static func createEmpty(at url: URL) throws {
        let attrs: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attrs)
        try (url as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
    }

    /// Mark an already-existing file complete-protected (idempotent).
    /// Safe to call after closing a streamed-write file to reassert the
    /// protection class.
    static func markProtected(at url: URL) throws {
        try (url as NSURL).setResourceValue(URLFileProtection.complete, forKey: .fileProtectionKey)
    }

    /// Append one line (+ newline) to a file, creating the parent dir and file with
    /// complete protection if needed, and re-asserting NSFileProtectionComplete after
    /// the write. Used for the encrypted per-casualty event JSONL.
    static func appendLine(_ line: String, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete])
        }
        if !fm.fileExists(atPath: url.path) {
            try createEmpty(at: url)
        }
        let handle = try FileHandle(forWritingTo: url)
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        try markProtected(at: url)
    }
}
