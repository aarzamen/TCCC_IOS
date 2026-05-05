// MedevacValidator
//
// Cross-references SLM-generated 9-Line MEDEVAC text against the deterministic
// `PatientStateEngine` snapshot and rewrites any disagreeing line. Mirrors
// `validate_medevac_against_state` in /Users/ama/TCCC_FEB_2026/src/reports.py
// (lines 20–92) verbatim.
//
// Why: SLMs hallucinate triage counts, drop tourniquets, or invent equipment
// requests. The state engine is the source of truth for everything Lines 3–5
// describe. Lines 1, 2, 6–9 are passed through (location, callsign, security,
// marking, nationality, CBRN — none of which the state engine knows about).
//
// Helpers (`StateHelpers.calculatePatientCounts`, `calculateLitterAmbulatory`,
// `determineSpecialEquipment`, `inferClassification`) are already ported in
// `StateHelpers.swift` for the deterministic fallback generator. The validator
// reuses them directly so MEDEVAC and ZMIST stay consistent by construction.
//
// Foundation only.

import Foundation
import TCCCDomain

/// Stateless validator for SLM-generated 9-Line MEDEVAC reports.
public enum MedevacValidator: Sendable {

    /// Validate an SLM-generated MEDEVAC. Cross-references Line 3 (Precedence
    /// counts), Line 4 (Special Equipment), and Line 5 (# Patients) against
    /// the supplied patient state. Lines 1, 2, 6–9 pass through.
    ///
    /// Mirrors `validate_medevac_against_state` (`reports.py:20–92`).
    ///
    /// - Parameters:
    ///   - medevacContent: Raw MEDEVAC text from the SLM.
    ///   - patients: Ordered list of patients from the engine snapshot
    ///     (insertion order matches Python's `state_engine.patients.values()`).
    ///   - transcript: Original ASR transcript, used for special-equipment
    ///     inference (hoist / extraction / ventilator).
    /// - Returns: Validated MEDEVAC text with state-verified counts.
    public static func validate(
        _ medevacContent: String,
        against patients: [PatientState],
        transcript: String = ""
    ) -> String {
        // Mirror Python: empty patient list short-circuits.
        if patients.isEmpty {
            return "No patients identified in assessment."
        }

        // Strip any chatty SLM preamble / postamble before line scanning.
        let stripped = SLMWrapperStripper.strip(medevacContent)

        // Pre-compute verified counts once per call.
        let counts = StateHelpers.calculatePatientCounts(patients)
        let split = StateHelpers.calculateLitterAmbulatory(patients)
        let equipment = StateHelpers.determineSpecialEquipment(
            transcript: transcript,
            patients: patients
        )

        var fixed: [String] = []
        let lines = stripped.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        for line in lines {
            // Order matters — check the most specific patterns first.

            // Line 4 — Special Equipment
            if hasLineLabel(line, label: "Line 4") {
                fixed.append("Line 4 (Special Equip):  \(equipment)")
                continue
            }

            // Line 5 — # Patients (litter / ambulatory)
            if hasLineLabel(line, label: "Line 5") {
                fixed.append(
                    "Line 5 (# Patients):     A-Litter: \(split.litter), B-Ambulatory: \(split.ambulatory)"
                )
                continue
            }

            // Expanded count rows (e.g. "         A - Urgent: 3").
            // Mirrors Python's `re.match(r'\s*\d*A\s*-\s*Urgent:', line)`.
            if matchesExpandedCount(line, letter: "A", label: "Urgent") {
                fixed.append(
                    "                         A - Urgent: \(counts.urgent)"
                )
                continue
            }
            if matchesExpandedCount(line, letter: "B", label: "Urgent Surgical") {
                fixed.append(
                    "                         B - Urgent Surgical: \(counts.urgentSurgical)"
                )
                continue
            }
            if matchesExpandedCount(line, letter: "C", label: "Priority") {
                fixed.append(
                    "                         C - Priority: \(counts.priority)"
                )
                continue
            }
            if matchesExpandedCount(line, letter: "D", label: "Routine") {
                fixed.append(
                    "                         D - Routine: \(counts.routine)"
                )
                continue
            }
            if matchesExpandedCount(line, letter: "E", label: "Convenience") {
                fixed.append(
                    "                         E - Convenience: \(counts.convenience)"
                )
                continue
            }

            // Line 3 — summary count format (A-1, B-0, C-0, D-0, E-0)
            if hasLineLabel(line, label: "Line 3") {
                let summary = "A-\(counts.urgent), B-\(counts.urgentSurgical), C-\(counts.priority), D-\(counts.routine), E-\(counts.convenience)"
                fixed.append("Line 3 (Precedence):     \(summary)")
                continue
            }

            // Pass-through.
            fixed.append(line)
        }

        return fixed.joined(separator: "\n")
    }

    // ------------------------------------------------------------------
    // Internal regex helpers
    // ------------------------------------------------------------------

    /// Mirrors `re.search(r'Line\s*N', line, re.IGNORECASE)` — case-insensitive
    /// match on the literal "Line" + optional whitespace + N anywhere in the
    /// line.
    private static func hasLineLabel(_ line: String, label: String) -> Bool {
        // `label` is "Line 3" / "Line 4" / "Line 5". Build "Line\s*N".
        guard let n = label.split(separator: " ").last else { return false }
        let pattern = "Line\\s*\(n)"
        return line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Mirrors `re.match(r'\s*\d*A\s*-\s*Urgent:', line, re.IGNORECASE)`.
    /// `re.match` anchors at the start of the string (not the line), and is
    /// case-insensitive here.
    private static func matchesExpandedCount(
        _ line: String,
        letter: String,
        label: String
    ) -> Bool {
        // Escape regex metacharacters in `label` so labels like
        // "Urgent Surgical" still work.
        let escapedLabel = NSRegularExpression.escapedPattern(for: label)
        let pattern = "^\\s*\\d*\(letter)\\s*-\\s*\(escapedLabel):"
        return line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// ----------------------------------------------------------------------
// SLM wrapper stripping (shared by both validators)
// ----------------------------------------------------------------------

/// Mirrors `_strip_slm_wrapper` from `reports.py:271–332`. Promoted to its own
/// type so the ZMIST validator can reuse it.
enum SLMWrapperStripper {

    /// Phrases that mark a line as conversational preamble (stripped).
    static let preambleIndicators: [String] = [
        "here is", "here's", "i've", "i have", "following",
        "generated", "based on", "below is",
    ]

    /// Phrases that mark a line as conversational postamble (stripped).
    static let postambleIndicators: [String] = [
        "note:", "please note", "i've followed", "i have followed",
        "i've generated", "i have generated", "i followed",
    ]

    static func strip(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        // Find the line that IS the report header (not a sentence containing
        // it). Mirrors the Python loop verbatim.
        var reportStartIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            let lineUpper = line.uppercased().trimmingCharacters(in: .whitespaces)
            let lineLower = line.lowercased()

            // Skip conversational preambles.
            if preambleIndicators.contains(where: { lineLower.contains($0) }) {
                continue
            }

            // Look for the actual header.
            if lineUpper == "9-LINE MEDEVAC REQUEST" {
                reportStartIdx = i
                break
            }
            if lineUpper == "ZMIST CASUALTY REPORT" {
                reportStartIdx = i
                break
            }
            // Match with equals signs / decoration: short header line with
            // "9-LINE MEDEVAC ... REQUEST" or "ZMIST ... REPORT".
            if lineUpper.contains("9-LINE MEDEVAC")
                && lineUpper.contains("REQUEST")
                && line.trimmingCharacters(in: .whitespaces).count < 50 {
                reportStartIdx = i
                break
            }
            if lineUpper.contains("ZMIST")
                && lineUpper.contains("REPORT")
                && line.trimmingCharacters(in: .whitespaces).count < 50 {
                reportStartIdx = i
                break
            }
        }

        // If we didn't find a header, start from beginning.
        let startIdx = reportStartIdx ?? 0

        var result: [String] = []
        for (i, line) in lines.enumerated() {
            if i < startIdx { continue }
            let lineLower = line.lowercased()
            // Skip postamble lines.
            if postambleIndicators.contains(where: { lineLower.contains($0) }) {
                continue
            }
            result.append(line)
        }

        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
