import Foundation

/// Typed vitals struct. Departs from the Python `vitals: dict` (`reports.py`
/// reads "HR", "BP", "SpO2", "RR", "GCS" keys) per the iOS design brief which
/// requires typed structs rather than dicts.
///
/// Out-of-range fields are silently dropped (set to nil) — never crashes.
public struct Vitals: Sendable, Codable, Equatable, Hashable {
    public let hr: Int?
    public let bp: BloodPressure?
    public let spo2: Int?
    public let rr: Int?
    public let gcs: Int?
    public let temperatureCelsius: Double?
    public let capillaryRefillSeconds: Double?

    /// Plausible physiological ranges. Out-of-range values are dropped.
    public static let hrRange: ClosedRange<Int> = 0...300
    public static let spo2Range: ClosedRange<Int> = 0...100
    public static let rrRange: ClosedRange<Int> = 0...80
    public static let gcsRange: ClosedRange<Int> = 3...15
    public static let temperatureRange: ClosedRange<Double> = 20.0...45.0
    public static let capillaryRefillRange: ClosedRange<Double> = 0.0...20.0

    /// Non-throwing initialiser. Values outside the documented ranges become
    /// `nil` instead of raising — there is no crash path.
    public init(
        hr: Int? = nil,
        bp: BloodPressure? = nil,
        spo2: Int? = nil,
        rr: Int? = nil,
        gcs: Int? = nil,
        temperatureCelsius: Double? = nil,
        capillaryRefillSeconds: Double? = nil
    ) {
        self.hr = hr.flatMap { Vitals.hrRange.contains($0) ? $0 : nil }
        self.bp = bp
        self.spo2 = spo2.flatMap { Vitals.spo2Range.contains($0) ? $0 : nil }
        self.rr = rr.flatMap { Vitals.rrRange.contains($0) ? $0 : nil }
        self.gcs = gcs.flatMap { Vitals.gcsRange.contains($0) ? $0 : nil }
        self.temperatureCelsius = temperatureCelsius.flatMap {
            Vitals.temperatureRange.contains($0) ? $0 : nil
        }
        self.capillaryRefillSeconds = capillaryRefillSeconds.flatMap {
            Vitals.capillaryRefillRange.contains($0) ? $0 : nil
        }
    }
}
