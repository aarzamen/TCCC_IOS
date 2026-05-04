// MedevacGenerator
//
// Produces the state-derived 9-Line MEDEVAC fallback. Mirrors
// `generate_medevac_from_state` in /Users/ama/TCCC_FEB_2026/src/reports.py
// (lines 335–384) for *logic*. The output text layout follows the iOS port
// contract specified in CLAUDE.md / Phase 5 task — a more compact line-prefixed
// block intended for on-screen display rather than the verbose Python
// formatting.
//
// Lines 6–9 default to the same TCCC defaults the Python prototype uses when
// no SLM is in the loop:
//   - Security:    "P · POSSIBLE ENEMY"
//   - Marking:     "C · SMOKE"
//   - Nationality: "A · US MIL"
//   - CBRN:        "N · NONE"
//
// Foundation only.

import Foundation
import TCCCDomain

/// State-derived 9-Line MEDEVAC fallback generator.
///
/// All instances are immutable value types; safe to pass across actor
/// boundaries.
public struct MedevacGenerator: Sendable {

    // MARK: Configurable header fields (Lines 1 + 2)

    public let callsign: String
    public let frequency: String
    public let location: String

    public init(
        callsign: String = "DUSTOFF 6",
        frequency: String = "38.65 FM",
        location: String = "MGRS UNKNOWN"
    ) {
        self.callsign = callsign
        self.frequency = frequency
        self.location = location
    }

    // MARK: Defaults for fields the engine does not know yet

    /// Mirrors Python `format_9line_template(security="N-No enemy", ...)` but
    /// uses the tactical-display string the Phase 5 contract requires.
    public static let defaultSecurity = "P · POSSIBLE ENEMY"
    public static let defaultMarking = "C · SMOKE"
    public static let defaultNationality = "A · US MIL"
    public static let defaultCBRN = "N · NONE"

    /// Banner emitted whenever this fallback path is taken. Matches the
    /// Python `save_9line_medevac(..., fallback=True)` banner intent.
    public static let fallbackBanner = "*** STATE-DERIVED FALLBACK, SLM UNAVAILABLE ***"

    // MARK: Generate

    /// Build a 9-Line MEDEVAC report from the supplied patient lineup. Counts,
    /// litter/ambulatory split, and special equipment all derive from
    /// `StateHelpers`, which mirrors the Python helpers verbatim.
    public func generate(
        from patients: [PatientState],
        at timestamp: Date = Date()
    ) -> Report {
        let body = format(patients: patients)
        return Report(
            kind: .nineLine,
            formattedText: body,
            generatedAt: timestamp,
            isFallback: true
        )
    }

    // MARK: Internal formatting

    private func format(patients: [PatientState]) -> String {
        // Empty-patient path mirrors the Python guard
        // (`if not patients: return "No patients identified in assessment."`).
        // We still emit the banner so the consumer can tell the report came
        // from the fallback path.
        if patients.isEmpty {
            return """
            \(MedevacGenerator.fallbackBanner)

            No patients identified in assessment.
            """
        }

        let counts = StateHelpers.calculatePatientCounts(patients)
        let split = StateHelpers.calculateLitterAmbulatory(patients)
        let equipment = StateHelpers.determineSpecialEquipment(
            transcript: "",
            patients: patients
        )

        let line3 = formatLine3(counts: counts)
        let line5 = formatLine5(split: split)

        return """
        \(MedevacGenerator.fallbackBanner)

        LINE 1: \(location)
        LINE 2: \(frequency) · \(callsign)
        LINE 3: \(line3)
        LINE 4: \(equipment)
        LINE 5: \(line5)
        LINE 6: \(MedevacGenerator.defaultSecurity)
        LINE 7: \(MedevacGenerator.defaultMarking)
        LINE 8: \(MedevacGenerator.defaultNationality)
        LINE 9: \(MedevacGenerator.defaultCBRN)
        """
    }

    /// Format Line 3: "<n> URGENT (A) / <n> PRIORITY (B) / <n> ROUTINE (C)".
    /// Folds Urgent Surgical into Urgent for the summary count (Python
    /// distinguishes these in the verbose breakdown but this layout collapses
    /// them — Urgent Surgical patients still need Urgent-class evac).
    private func formatLine3(counts: PatientCounts) -> String {
        let urgent = counts.urgent + counts.urgentSurgical
        return "\(urgent) URGENT (A) / \(counts.priority) PRIORITY (B) / \(counts.routine) ROUTINE (C)"
    }

    /// Format Line 5: "L<litter> · A<ambulatory>  ·  <total> total".
    /// The double-space before the bullet is intentional — matches the spec.
    private func formatLine5(split: LitterAmbulatory) -> String {
        return "L\(split.litter) · A\(split.ambulatory)  ·  \(split.total) total"
    }
}
