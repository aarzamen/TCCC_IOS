// HeadHypothermiaExtractor
//
// Faithful Swift port of `_extract_head_hypothermia` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 766–797). The H of MARCH.
//
// Pattern definitions live in `_compile_patterns` around lines 427–440:
//
//     self.head_patterns = {
//         "avpu": [
//             (re.compile(r"\balert\b|\boriented\b|a\s*and\s*o|alert\s*and\s*oriented", re.I), "Alert"),
//             (re.compile(r"responds?\s*to\s*voice|voice\s*responsive", re.I), "Voice"),
//             (re.compile(r"responds?\s*to\s*pain|pain\s*responsive", re.I), "Pain"),
//             (re.compile(r"unresponsive|unconscious|u\s*on\s*avpu", re.I), "Unresponsive"),
//         ],
//         "pupils": [
//             (re.compile(r"pupils?\s*(are\s*)?(equal|unequal|dilated|constricted|reactive|fixed)", re.I), <lambda>),
//             (re.compile(r"(equal|unequal)\s*(and\s*)?(reactive|fixed)", re.I), <lambda>),
//         ],
//         "hypothermia": re.compile(r"hypothermia\s*wrap|prevent\s*hypothermia|wrapping|blanket|insulate", re.I),
//         "gcs": re.compile(r"gcs\s*(?:is\s*|of\s*)?(\d+)", re.I),
//     }
//
// Python dispatch (state.py:766–797):
//   - Walk avpu list; first match wins -> march.consciousness = status
//   - Walk pupils list; first match wins -> march.pupil_response = extracted
//   - If hypothermia matches -> hypothermia_prevention = "Hypothermia wrap applied"
//                              + interventions.append("Hypothermia prevention measures")
//   - If gcs matches -> patient.vitals["GCS"] = int(group 1)
//
// Negation: Python does not consult `has_negated_finding` here. We mirror
// that — context.isNegated is informational only.
//
// Foundation only.

import Foundation
import TCCCDomain

public struct HeadHypothermiaExtractor: ExtractorPass {

    // MARK: - Patterns

    private let avpuAlert: NSRegularExpression
    private let avpuVoice: NSRegularExpression
    private let avpuPain: NSRegularExpression
    private let avpuUnresponsive: NSRegularExpression

    private let pupilsBasic: NSRegularExpression
    private let pupilsCombined: NSRegularExpression

    private let hypothermia: NSRegularExpression
    private let gcs: NSRegularExpression

    public init() {
        self.avpuAlert = try! NSRegularExpression(
            pattern: "\\balert\\b|\\boriented\\b|a\\s*and\\s*o|alert\\s*and\\s*oriented",
            options: [.caseInsensitive])
        self.avpuVoice = try! NSRegularExpression(
            pattern: "responds?\\s*to\\s*voice|voice\\s*responsive",
            options: [.caseInsensitive])
        self.avpuPain = try! NSRegularExpression(
            pattern: "responds?\\s*to\\s*pain|pain\\s*responsive",
            options: [.caseInsensitive])
        self.avpuUnresponsive = try! NSRegularExpression(
            pattern: "unresponsive|unconscious|u\\s*on\\s*avpu",
            options: [.caseInsensitive])

        self.pupilsBasic = try! NSRegularExpression(
            pattern: "pupils?\\s*(are\\s*)?(equal|unequal|dilated|constricted|reactive|fixed)",
            options: [.caseInsensitive])
        self.pupilsCombined = try! NSRegularExpression(
            pattern: "(equal|unequal)\\s*(and\\s*)?(reactive|fixed)",
            options: [.caseInsensitive])

        self.hypothermia = try! NSRegularExpression(
            pattern: "hypothermia\\s*wrap|prevent\\s*hypothermia|wrapping|blanket|insulate",
            options: [.caseInsensitive])
        self.gcs = try! NSRegularExpression(
            pattern: "gcs\\s*(?:is\\s*|of\\s*)?(\\d+)",
            options: [.caseInsensitive])
    }

    // MARK: - Apply

    public func apply(_ state: PatientState, context: ExtractionContext) -> PatientState {
        var s = state
        var march = s.march
        let text = context.sentence

        // AVPU — first match wins (Python iterates in order and breaks).
        let avpuTable: [(NSRegularExpression, String)] = [
            (avpuAlert, "Alert"),
            (avpuVoice, "Voice"),
            (avpuPain, "Pain"),
            (avpuUnresponsive, "Unresponsive"),
        ]
        for (pattern, status) in avpuTable {
            if matches(pattern, text) {
                march.consciousness = status
                break
            }
        }

        // Pupils — try basic, then combined; first match wins.
        if let pupilDesc = extractPupilsBasic(text) {
            march.pupilResponse = pupilDesc
        } else if let pupilDesc = extractPupilsCombined(text) {
            march.pupilResponse = pupilDesc
        }

        // Hypothermia prevention.
        if matches(hypothermia, text) {
            march.hypothermiaPrevention = "Hypothermia wrap applied"
            let existing = s.interventions.map { $0.description.lowercased() }
                .joined(separator: "|")
            if !existing.contains("hypothermia") {
                s.interventions.append(Intervention(
                    timestamp: context.timestamp,
                    kind: .hypothermiaPrevention,
                    description: "Hypothermia prevention measures"))
            }
        }

        // GCS — assign to typed Vitals.gcs (Vitals validates via init range).
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        if let m = gcs.firstMatch(in: text, options: [], range: fullRange),
           m.numberOfRanges > 1 {
            let r = m.range(at: 1)
            if r.location != NSNotFound,
               let value = Int(nsText.substring(with: r)) {
                // Re-build Vitals so the range validator runs.
                s.vitals = Vitals(
                    hr: s.vitals.hr,
                    bp: s.vitals.bp,
                    spo2: s.vitals.spo2,
                    rr: s.vitals.rr,
                    gcs: value,
                    temperatureCelsius: s.vitals.temperatureCelsius,
                    capillaryRefillSeconds: s.vitals.capillaryRefillSeconds)
            }
        }

        s.march = march
        return s
    }

    // MARK: - Pupil extraction
    //
    // Both lambdas in Python read the captured groups verbatim. We do the
    // same and trim trailing whitespace so the assertion strings match.

    private func extractPupilsBasic(_ text: String) -> String? {
        let nsText = text as NSString
        let r = NSRange(location: 0, length: nsText.length)
        guard let m = pupilsBasic.firstMatch(in: text, options: [], range: r),
              m.numberOfRanges > 2 else { return nil }
        let g2r = m.range(at: 2)
        guard g2r.location != NSNotFound else { return nil }
        let result = nsText.substring(with: g2r)
        return result.isEmpty ? nil : result.lowercased()
    }

    private func extractPupilsCombined(_ text: String) -> String? {
        let nsText = text as NSString
        let r = NSRange(location: 0, length: nsText.length)
        guard let m = pupilsCombined.firstMatch(in: text, options: [], range: r),
              m.numberOfRanges > 3 else { return nil }
        let g1r = m.range(at: 1)
        let g3r = m.range(at: 3)
        guard g1r.location != NSNotFound, g3r.location != NSNotFound else { return nil }
        let g1 = nsText.substring(with: g1r)
        let g3 = nsText.substring(with: g3r)
        return "\(g1) and \(g3)".lowercased()
    }

    // MARK: - Helpers

    private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let nsText = text as NSString
        let r = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: r) != nil
    }
}
