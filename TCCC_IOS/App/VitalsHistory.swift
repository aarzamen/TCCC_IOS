import Foundation
import TCCCDomain

/// One frozen vitals reading bound to wall-clock time. Used by the Screen 02
/// trend chart to draw a 15-minute rolling window of HR / BP-systolic / SpO₂.
struct VitalsHistorySample: Sendable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let hr: Int?
    let systolic: Int?
    let diastolic: Int?
    let spo2: Int?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        hr: Int?,
        systolic: Int?,
        diastolic: Int?,
        spo2: Int?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.hr = hr
        self.systolic = systolic
        self.diastolic = diastolic
        self.spo2 = spo2
    }
}

/// Append-only ring of vitals samples bounded by `retention`. Holds the last
/// 15 min of readings as recorded by the patient-state engine each time the
/// snapshot refreshes (i.e., once per processed transcript chunk).
///
/// Behaviour notes:
/// - `record(from:at:)` skips samples where every field is nil (keeps the
///   chart from filling with placeholder noise before any extraction).
/// - `samples` stays sorted by timestamp ascending (insertion order).
/// - Old samples outside `retention` are evicted on every `record` call.
struct VitalsHistory: Sendable {
    private(set) var samples: [VitalsHistorySample] = []

    /// 15 min trailing window (matches the Screen 02 panel title).
    let retention: TimeInterval = 15 * 60

    /// Append a sample derived from `vitals`. No-op if every field is nil.
    mutating func record(from vitals: Vitals, at timestamp: Date) {
        let sys = vitals.bp?.systolic
        let dia = vitals.bp?.diastolic
        let allNil = vitals.hr == nil && sys == nil && vitals.spo2 == nil
        if allNil { return }

        let sample = VitalsHistorySample(
            timestamp: timestamp,
            hr: vitals.hr,
            systolic: sys,
            diastolic: dia,
            spo2: vitals.spo2
        )
        samples.append(sample)
        evictExpired(now: timestamp)
    }

    /// Evict anything outside the trailing window.
    private mutating func evictExpired(now: Date) {
        let cutoff = now.addingTimeInterval(-retention)
        samples.removeAll { $0.timestamp < cutoff }
    }

    /// Down-sample to roughly `count` evenly-spaced samples for charting.
    /// If history is shorter than `count`, returns it unchanged.
    func sampledForDisplay(_ count: Int = 60) -> [VitalsHistorySample] {
        guard samples.count > count, count > 1 else { return samples }
        let step = Double(samples.count - 1) / Double(count - 1)
        var out: [VitalsHistorySample] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let idx = Int((Double(i) * step).rounded())
            out.append(samples[min(idx, samples.count - 1)])
        }
        return out
    }
}
