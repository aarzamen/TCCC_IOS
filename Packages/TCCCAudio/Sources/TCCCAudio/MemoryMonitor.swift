import Darwin
import Foundation
import os

/// Foreground-app memory observer for Granite Speech model load and
/// inference (Sprint 1 v3 §7).
///
/// Publishes three readings plus a pressure level:
/// - **residentMB** — `task_basic_info.resident_size`. Coarse
///   "how much have we paged in" — useful for trends, not for the
///   jetsam ceiling.
/// - **physFootprintMB** — `task_vm_info.phys_footprint`. **The metric
///   jetsam fires on** (Apple Developer Forums #770868). Use this
///   as the signal for runtime cap decisions.
/// - **availableMB** — `os_proc_available_memory()`. Bytes the app
///   can still allocate before jetsam — already wrapped by
///   `MemoryStat` in the app target, but we mirror it here so this
///   monitor is self-contained inside the package.
///
/// Cap is **runtime-computed** at first read:
/// `cap = phys_footprint + available` measured at app launch.
/// Warning at 75% × cap; critical at 90% × cap. v3 explicitly
/// rejected the v1 spec's hard 3.5 GB ceiling — actual cap depends
/// on device + entitlement state, which the runtime sees but the
/// spec author can't.
///
/// Thread-safety: methods are synchronous and read-only against
/// kernel APIs; no cross-actor state. Suitable to call from any
/// isolation. The `Observer` class wires a SwiftUI-friendly
/// `@MainActor`-published view and a system memory-pressure
/// subscription on top.
public enum MemoryMonitor {

    public struct Reading: Sendable, Equatable {
        public let residentBytes: UInt64
        public let physFootprintBytes: UInt64
        public let availableBytes: UInt64
        public let timestamp: Date

        public var residentMB: Double { Double(residentBytes) / 1_048_576.0 }
        public var physFootprintMB: Double { Double(physFootprintBytes) / 1_048_576.0 }
        public var availableMB: Double { Double(availableBytes) / 1_048_576.0 }

        public init(
            residentBytes: UInt64,
            physFootprintBytes: UInt64,
            availableBytes: UInt64,
            timestamp: Date = Date()
        ) {
            self.residentBytes = residentBytes
            self.physFootprintBytes = physFootprintBytes
            self.availableBytes = availableBytes
            self.timestamp = timestamp
        }
    }

    public enum Pressure: String, Sendable, Equatable {
        case normal
        case warning
        case critical
    }

    public static func reading() -> Reading {
        Reading(
            residentBytes: residentBytes(),
            physFootprintBytes: physFootprintBytes(),
            availableBytes: availableBytes()
        )
    }

    /// `phys_footprint` from `task_vm_info`. The number iOS's jetsam
    /// daemon actually monitors. Returns 0 if the syscall fails.
    public static func physFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    /// `resident_size` from `mach_task_basic_info`. Reported as the
    /// first metric for compatibility with existing memory dashboards;
    /// not the jetsam signal.
    public static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }

    /// Bytes the process can allocate before iOS jetsam-kills it.
    /// Returns 0 on simulator / older iOS where the API is no-op.
    public static func availableBytes() -> UInt64 {
        #if os(iOS)
        return UInt64(os_proc_available_memory())
        #else
        return 0
        #endif
    }
}

// MARK: - Observer (SwiftUI-friendly)

/// Lightweight observer that polls `MemoryMonitor.reading()` on a
/// timer and publishes the result on the main actor. Also subscribes
/// to system memory pressure events via `DispatchSource`.
///
/// This is a **value-publisher**, not the Granite Speech runtime's
/// owner — it's safe to instantiate one per view that wants live
/// updates. Stop polling by calling `stop()` or letting the instance
/// deallocate.
@MainActor
@Observable
public final class MemoryMonitorObserver {
    public private(set) var current: MemoryMonitor.Reading
    public private(set) var pressure: MemoryMonitor.Pressure = .normal

    /// Cap snapshot taken at first observe. Subsequent readings are
    /// thresholded against this cap.
    public let baselineCapBytes: UInt64

    /// 75% × baseline cap.
    public var warningThresholdBytes: UInt64 { baselineCapBytes / 100 * 75 }

    /// 90% × baseline cap.
    public var criticalThresholdBytes: UInt64 { baselineCapBytes / 100 * 90 }

    private var timer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private let pollInterval: TimeInterval

    public init(pollInterval: TimeInterval = 1.0) {
        let initialReading = MemoryMonitor.reading()
        self.current = initialReading
        self.baselineCapBytes = initialReading.physFootprintBytes + initialReading.availableBytes
        self.pollInterval = pollInterval
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        subscribeMemoryPressure()
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        pressureSource?.cancel()
        pressureSource = nil
    }

    private func tick() {
        let reading = MemoryMonitor.reading()
        current = reading
        if reading.physFootprintBytes >= criticalThresholdBytes {
            pressure = .critical
        } else if reading.physFootprintBytes >= warningThresholdBytes {
            pressure = .warning
        } else {
            pressure = .normal
        }
    }

    private func subscribeMemoryPressure() {
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            let event = src.data
            Task { @MainActor [weak self] in
                guard let self else { return }
                if event.contains(.critical) {
                    self.pressure = .critical
                } else if event.contains(.warning), self.pressure != .critical {
                    self.pressure = .warning
                }
            }
        }
        src.resume()
        self.pressureSource = src
    }

    // Note: no deinit cleanup. Callers MUST invoke `stop()` before
    // releasing the observer. Swift 6's strict-concurrency rules
    // forbid reaching @MainActor-isolated mutable state from a
    // nonisolated `deinit`, and the alternative (pulling the class
    // out of @MainActor) churns the SwiftUI observation surface for
    // no real safety win — Timer/DispatchSource leak harmlessly if
    // the observer outlives its caller.
}

// MARK: - CSV log

/// Append-only CSV logger for memory readings. Useful for jetsam
/// forensics on long recordings (write a row every N seconds during
/// inference; if the app dies, the last few rows show what was
/// happening).
///
/// Lives in `Documents/MemoryMonitorLog.csv` per v3 §7.
public final class MemoryMonitorCSVLogger: @unchecked Sendable {
    public let url: URL
    private let queue = DispatchQueue(label: "tccc.memorymonitor.csv")
    private var hasHeader: Bool = false

    public init(directory: URL? = nil) {
        let dir: URL
        if let provided = directory {
            dir = provided
        } else {
            dir = (try? FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.temporaryDirectory
        }
        self.url = dir.appendingPathComponent("MemoryMonitorLog.csv")
        self.hasHeader = FileManager.default.fileExists(atPath: url.path)
    }

    public func append(_ reading: MemoryMonitor.Reading, pressure: MemoryMonitor.Pressure, event: String = "") {
        queue.async { [self] in
            let line: String = {
                let stamp = ISO8601DateFormatter().string(from: reading.timestamp)
                return "\(stamp),\(reading.residentBytes),\(reading.physFootprintBytes),\(reading.availableBytes),\(pressure.rawValue),\(event.replacingOccurrences(of: ",", with: ";"))\n"
            }()
            if !hasHeader {
                let header = "timestamp_iso,resident_bytes,phys_footprint_bytes,available_bytes,pressure,event\n"
                try? header.write(to: url, atomically: false, encoding: .utf8)
                hasHeader = true
            }
            if let data = (line.data(using: .utf8)),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            }
        }
    }
}
