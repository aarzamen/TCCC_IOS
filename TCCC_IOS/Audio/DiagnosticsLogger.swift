import Foundation
import os
import os.log

/// Append-only diagnostics logger for the capture-rate root-cause pass.
///
/// Mirrors every log call to:
///   1. `os_log` under subsystem `com.tccc.audio` so it shows up in
///      Console.app via the standard live-stream path
///   2. A flat text file at `Documents/diagnostics/run-{stamp}.log` so
///      the operator can pull the diagnostic record alongside the
///      transcript .txt and encounter .m4a via the existing share sheet
///
/// The file path is NSFileProtectionComplete-protected (it can contain
/// transcript fragments).
///
/// Public `log(...)` is `nonisolated` so it's safe to call from the
/// AVAudioEngine render thread. The os_log call lands inline (designed to
/// be non-blocking); the file-write hops to the actor's serial queue so
/// the render thread never waits on disk I/O.
actor DiagnosticsLogger {
    static let shared = DiagnosticsLogger()

    nonisolated private static let osLog = OSLog(
        subsystem: "com.tccc.audio",
        category: "diagnostics"
    )

    private var fileHandle: FileHandle?
    private(set) var currentLogURL: URL?

    /// Lazily-allocated formatter. Each `writeLine` call hits the actor
    /// queue, so we can hold the (non-Sendable) formatter as actor state.
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Open a new log file for the current session. Returns the URL (also
    /// stored on the actor) so callers can stash it for later sharing.
    func startSession() -> URL? {
        if fileHandle != nil { closeFile() }

        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = docs.appendingPathComponent("diagnostics", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let stampF = DateFormatter()
        stampF.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = stampF.string(from: Date())
        let url = dir.appendingPathComponent("run-\(stamp).log")
        try? ProtectedWrite.createEmpty(at: url)
        fileHandle = try? FileHandle(forWritingTo: url)
        currentLogURL = url
        writeLine("=== diagnostics session start · \(stamp) ===", category: "session")
        return url
    }

    /// Flush + close the current session's file. Idempotent.
    func endSession() {
        writeLine("=== diagnostics session end ===", category: "session")
        closeFile()
    }

    /// Public entry — safe from any thread. Forwards to os_log inline +
    /// hops to the actor for the file write.
    nonisolated func log(_ message: String, category: String = "diag") {
        os_log(
            "%{public}s · %{public}s",
            log: Self.osLog,
            type: .default,
            category,
            message
        )
        Task { await self.writeLine(message, category: category) }
    }

    private func writeLine(_ message: String, category: String) {
        guard let fileHandle else { return }
        let timestamp = isoFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)\n"
        if let data = line.data(using: .utf8) {
            try? fileHandle.write(contentsOf: data)
        }
    }

    private func closeFile() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}

/// Throttled buffer-arrival counter. Tracks how many AVAudioEngine tap
/// buffers fired since the last emit, plus the most recent RMS sample.
/// The audio render thread updates this with simple atomics; the
/// 1-second heartbeat reads + resets it.
///
/// Lives outside `DiagnosticsLogger` because the actor's isolation would
/// force a Task hop on every buffer (~16-46/sec). This tiny class has
/// `OSAllocatedUnfairLock`-backed integer math — same pattern as
/// `AudioGainBox` from the hardening sprint.
final class BufferArrivalCounter: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<State>(initialState: State())

    struct State {
        var count: Int = 0
        var lastRMS: Float = 0
        var totalFrames: Int = 0
    }

    func record(frames: Int, rms: Float) {
        lock.withLock { state in
            state.count += 1
            state.lastRMS = rms
            state.totalFrames += frames
        }
    }

    /// Atomic read-and-reset. Returns the previous window's stats.
    func drain() -> State {
        lock.withLock { state in
            let snapshot = state
            state = State()
            return snapshot
        }
    }
}
