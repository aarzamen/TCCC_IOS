import Foundation
import Darwin

/// Foreground-app memory headroom probe. Per night-pass A3
/// (2026-05-05) and RESEARCH_RAM_API.md.
///
/// `os_proc_available_memory()` returns the bytes the process can
/// still allocate before iOS jetsam-kills it. Apple recommends this
/// over `task_info` for adaptive memory display because it accounts
/// for system pressure, not just resident size.
///
/// Stateless / cheap — call `MemoryStat.availableBytes()` from a
/// SwiftUI `TimelineView` tick. No timer to manage, no actor
/// isolation to worry about, no deinit cleanup.
enum MemoryStat {
    /// Bytes available to this app before the kernel will jetsam-kill
    /// it. Returns `nil` on simulator / older iOS where the API
    /// returns 0.
    static func availableBytes() -> UInt64? {
        #if os(iOS)
        let value = os_proc_available_memory()
        return value > 0 ? UInt64(value) : nil
        #else
        return nil
        #endif
    }

    /// Convenience: same as availableBytes() but rendered as a short
    /// chip label ("1.2 G", "480 M", "—").
    static func chipLabel() -> String {
        guard let bytes = availableBytes() else { return "—" }
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f G", gb)
        }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0f M", mb)
    }

    /// Coarse threshold for UI color — `.crit` below 200 MB available,
    /// `.warn` below 500 MB, otherwise neutral.
    enum Pressure { case normal, warn, crit, unknown }

    static func pressure() -> Pressure {
        guard let bytes = availableBytes() else { return .unknown }
        let mb = Double(bytes) / 1_048_576.0
        if mb < 200 { return .crit }
        if mb < 500 { return .warn }
        return .normal
    }
}
