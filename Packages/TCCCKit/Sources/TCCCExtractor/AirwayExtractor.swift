// AirwayExtractor
//
// Faithful Swift port of `_extract_airway` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 663–681). The A of MARCH.
//
// Pattern definitions live in `_compile_patterns` around lines 390–395:
//
//     self.airway_patterns = {
//         "patent":     re.compile(r"airway\s*(is\s*)?(patent|clear|open)|talking|conscious.*talk", re.I),
//         "compromised":re.compile(r"airway.*(compromised|obstruct|block)", re.I),
//         "npa":        re.compile(r"npa|nasopharyngeal|nasal\s*airway", re.I),
//         "cric":       re.compile(r"cric|cricothyroidotomy|surgical\s*airway", re.I),
//     }
//
// Python dispatch:
//   - If "patent" matches -> march.airway_status = "patent"
//   - elif "compromised" matches -> march.airway_status = "compromised"
//   - If "npa" matches -> intervention = "NPA inserted", append intervention
//   - elif "cric" matches -> intervention = "Surgical cricothyroidotomy"
//
// Negation note: the Python `_extract_airway` does NOT consult
// `has_negated_finding`. We mirror that — context.isNegated is informational
// only. The "patent" branch already encodes positive language ("airway is
// patent", "talking", etc.), so a sentence like "no airway compromise" hits
// the `\bno\b` negation marker but the patent regex won't match either, and
// the compromised regex won't match because there's no "airway" to anchor it.
//
// Foundation only.

import Foundation
import TCCCDomain

public struct AirwayExtractor: ExtractorPass {

    private let patent: NSRegularExpression
    private let compromised: NSRegularExpression
    private let npa: NSRegularExpression
    private let cric: NSRegularExpression

    public init() {
        self.patent = try! NSRegularExpression(
            pattern: "airway\\s*(is\\s*)?(patent|clear|open)|talking|conscious.*talk",
            options: [.caseInsensitive])
        self.compromised = try! NSRegularExpression(
            pattern: "airway.*(compromised|obstruct|block)",
            options: [.caseInsensitive])
        self.npa = try! NSRegularExpression(
            pattern: "npa|nasopharyngeal|nasal\\s*airway",
            options: [.caseInsensitive])
        self.cric = try! NSRegularExpression(
            pattern: "cric|cricothyroidotomy|surgical\\s*airway",
            options: [.caseInsensitive])
    }

    public func apply(_ state: PatientState, context: ExtractionContext) -> PatientState {
        var s = state
        var march = s.march
        let text = context.sentence

        // Status: Python uses if/elif so patent wins over compromised.
        if matches(patent, text) {
            march.airwayStatus = "patent"
        } else if matches(compromised, text) {
            march.airwayStatus = "compromised"
        }

        // Interventions: NPA branch wins over cric branch (Python if/elif).
        if matches(npa, text) {
            march.airwayIntervention = "NPA inserted"
            // Python: `if "NPA" not in str(patient.interventions)`
            let existing = s.interventions.map { $0.description }.joined(separator: "|")
            if !existing.contains("NPA") {
                s.interventions.append(Intervention(
                    timestamp: context.timestamp,
                    kind: .npa,
                    description: "NPA inserted"))
            }
        } else if matches(cric, text) {
            march.airwayIntervention = "Surgical cricothyroidotomy"
            // Python: `if "cric" not in str(patient.interventions).lower()`
            let existing = s.interventions.map { $0.description.lowercased() }
                .joined(separator: "|")
            if !existing.contains("cric") {
                s.interventions.append(Intervention(
                    timestamp: context.timestamp,
                    kind: .surgicalAirway,
                    description: "Surgical cricothyroidotomy"))
            }
        }

        s.march = march
        return s
    }

    // MARK: - Helpers

    private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let nsText = text as NSString
        let r = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: r) != nil
    }
}
