import Foundation

/// Blood pressure reading.
///
/// In the Python prototype BP is stored as a string ("120/80") in the vitals
/// dict. The Swift port uses a typed struct per the design brief. `palpated`
/// mirrors the Python "P" suffix convention (e.g. "90/P" for a palpated
/// systolic with no measurable diastolic).
public struct BloodPressure: Sendable, Codable, Equatable, Hashable {
    public let systolic: Int
    public let diastolic: Int
    public let palpated: Bool

    public init(systolic: Int, diastolic: Int, palpated: Bool = false) {
        self.systolic = systolic
        self.diastolic = diastolic
        self.palpated = palpated
    }
}
