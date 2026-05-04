import Foundation

/// Post-MARCH PAWS assessment: Pain, Antibiotics, Wounds, Splinting.
///
/// In the Python prototype (`state.py:_extract_paws`, lines 898–929) PAWS
/// findings are appended as descriptor strings into the patient's
/// `interventions` list — there is no dedicated PAWS dataclass. The iOS design
/// brief calls for PAWS to be a top-level typed struct, so this Swift mirror
/// extracts the four categories into their own optional descriptor fields.
public struct PAWSAssessment: Sendable, Codable, Equatable, Hashable {
    /// e.g. "Combat pill pack administered", "Ketamine administered".
    public var pain: String?
    /// e.g. "Moxifloxacin administered".
    public var antibiotics: String?
    /// e.g. "Wound care performed".
    public var wounds: String?
    /// e.g. "SAM splint", "Traction splint (Sager)".
    public var splinting: String?

    public init(
        pain: String? = nil,
        antibiotics: String? = nil,
        wounds: String? = nil,
        splinting: String? = nil
    ) {
        self.pain = pain
        self.antibiotics = antibiotics
        self.wounds = wounds
        self.splinting = splinting
    }
}
