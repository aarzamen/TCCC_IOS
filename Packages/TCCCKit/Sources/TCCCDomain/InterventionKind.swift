import Foundation

/// Categories of interventions. Mirrors the distinct
/// `patient.interventions.append(...)` call sites in `state.py` (tourniquet,
/// pressure dressing, NPA, surgical cricothyroidotomy, chest seal, needle
/// decompression, IV/IO access, hypothermia, splint, pain meds, antibiotics,
/// wound care).
public enum InterventionKind: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case tourniquet
    case pressureDressing
    case dressing
    case npa
    case surgicalAirway
    case chestSeal
    case needleDecompression
    case ivAccess
    case ioAccess
    case medication
    case antibiotic
    case painManagement
    case woundCare
    case splint
    case hypothermiaPrevention
    case other
}
