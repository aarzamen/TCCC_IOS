import Foundation

/// MARCH assessment phase. Raw values mirror the single-letter keys used in
/// `state.py:get_phase_status` ("M", "A", "R", "C", "H").
public enum MarchPhase: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case massive = "M"
    case airway = "A"
    case respiration = "R"
    case circulation = "C"
    case head = "H"
}

/// Status indicator for a MARCH phase.
/// Raw values mirror the glyphs returned by `state.py:get_phase_status`:
/// "✓" (assessed/done), "·" (partial / in progress), "-" (not started).
public enum PhaseStatus: String, Sendable, Codable, Equatable, Hashable {
    case done = "✓"
    case inProgress = "·"
    case notAssessed = "-"
}

/// TCCC triage classification. Raw values match the strings produced by
/// `state.py:_extract_classification` and `state.py:infer_classification`.
public enum Classification: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case urgent = "Urgent"
    case urgentSurgical = "Urgent Surgical"
    case priority = "Priority"
    case routine = "Routine"
    case expectant = "Expectant"
}

/// Airway status. Raw values mirror the lowercase strings written by
/// `state.py` (e.g. `march.airway_status = "patent"`).
public enum AirwayStatus: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case patent = "patent"
    case compromised = "compromised"
    case obstructed = "obstructed"
}

/// AVPU consciousness level. Raw values match the capitalised strings written
/// by `state.py` (e.g. `march.consciousness = "Alert"`).
public enum ConsciousnessLevel: String, Sendable, Codable, Equatable, Hashable, CaseIterable {
    case alert = "Alert"
    case voice = "Voice"
    case pain = "Pain"
    case unresponsive = "Unresponsive"
}
