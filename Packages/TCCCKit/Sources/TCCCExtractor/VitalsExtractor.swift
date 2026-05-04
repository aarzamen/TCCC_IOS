// VitalsExtractor
//
// Faithful Swift port of `_extract_vitals` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 799–820), plus the four
// numeric vital-sign regex patterns defined at lines 442–448:
//
//     vitals_patterns = {
//         "hr":   re.compile(r"(?:heart\s*rate|hr|pulse)\s*(?:is\s*|of\s*)?(\d+)", re.I),
//         "bp":   re.compile(r"(?:blood\s*pressure|bp)\s*(?:is\s*)?(\d+)\s*(?:over|/)\s*(\d+)", re.I),
//         "spo2": re.compile(r"(?:pulse\s*ox|spo2|sat|o2\s*sat)\s*(?:is\s*)?(\d+)\s*%?", re.I),
//         "rr":   re.compile(r"(?:respiratory\s*rate|rr)\s*(?:is\s*|looks?\s*(?:about\s*)?)?(\d+)", re.I),
//     }
//
// This pass operates on `context.sentence`, which the engine has already
// normalised via `SpokenNumberNormalizer` — so spoken forms like
// "heart rate one ten" arrive here as "heart rate 110" and the digit-only
// regex above is sufficient.
//
// Two principled extensions over the Python source:
//
//   1. `BloodPressure.palpated` — the Python prototype stores BP as a string
//      ("90/60"); the Swift `BloodPressure` struct adds a `palpated: Bool`
//      flag, populated from a trailing "P" / "/P" / "palp" / "palpated"
//      token (e.g. "BP 80/40 P", "BP 90/P palpated"). Python doesn't model
//      this, so there's no behavioural divergence — Python silently loses
//      the suffix; Swift records it.
//
//   2. `context.isNegated` — when the engine flags a sentence as negated
//      (e.g. "no measurable BP", "no pulse"), this extractor refuses to
//      record any vital sign. Python's `_extract_vitals` lacks this guard
//      because vitals weren't part of the negation regression in P2; the
//      design brief asks all extractors to honour the flag uniformly.
//
// GCS is intentionally NOT extracted here — the Python prototype routes
// GCS through `_extract_head_hypothermia` (Lane A's `HeadHypothermiaExtractor`),
// not `_extract_vitals`.
//
// Foundation only — no SwiftUI, UIKit, Combine, or external deps.

import Foundation
import TCCCDomain

public struct VitalsExtractor: ExtractorPass {

    // MARK: - Compiled regex patterns
    //
    // Patterns mirror the Python `vitals_patterns` dict at state.py:443–448,
    // with `bp` extended to capture an optional palpated marker.

    private let hrRegex: NSRegularExpression
    private let bpRegex: NSRegularExpression
    private let spo2Regex: NSRegularExpression
    private let rrRegex: NSRegularExpression

    public init() {
        // Heart rate. Group 1 = numeric value.
        let hrPattern =
            "(?:heart\\s*rate|hr|pulse)\\s*(?:is\\s*|of\\s*)?(\\d+)"

        // Blood pressure. Group 1 = systolic, group 2 = diastolic, group 3 =
        // optional palpated marker. Python pattern:
        //   r"(?:blood\s*pressure|bp)\s*(?:is\s*)?(\d+)\s*(?:over|/)\s*(\d+)"
        // Swift extends with an optional palpated suffix (whitespace + "P" /
        // "palp" / "palpated", case-insensitive). The marker is OUTSIDE the
        // Python contract — it consumes characters Python would have left in
        // the sentence — so the Python truth (sys/dia integers) is preserved.
        let bpPattern =
            "(?:blood\\s*pressure|bp)\\s*(?:is\\s*)?" +
            "(\\d+)\\s*(?:over|/)\\s*(\\d+)" +
            "(?:\\s*(?:/\\s*)?(p(?:alp(?:ated)?)?))?\\b"

        // SpO2 / pulse-ox / sat. Group 1 = numeric value (0–100).
        let spo2Pattern =
            "(?:pulse\\s*ox|spo2|sat|o2\\s*sat)\\s*(?:is\\s*)?(\\d+)\\s*%?"

        // Respiratory rate. Group 1 = numeric value.
        let rrPattern =
            "(?:respiratory\\s*rate|rr)\\s*(?:is\\s*|looks?\\s*(?:about\\s*)?)?(\\d+)"

        // Force-unwraps are safe: these are static literals validated by the
        // test suite. A failure here is a programmer error.
        self.hrRegex = try! NSRegularExpression(
            pattern: hrPattern, options: [.caseInsensitive])
        self.bpRegex = try! NSRegularExpression(
            pattern: bpPattern, options: [.caseInsensitive])
        self.spo2Regex = try! NSRegularExpression(
            pattern: spo2Pattern, options: [.caseInsensitive])
        self.rrRegex = try! NSRegularExpression(
            pattern: rrPattern, options: [.caseInsensitive])
    }

    // MARK: - ExtractorPass

    public func apply(
        _ state: PatientState, context: ExtractionContext
    ) -> PatientState {
        // Honour the engine-supplied negation flag — refuse to record vitals
        // when the sentence is tagged negated. (See file-header note 2.)
        if context.isNegated {
            return state
        }

        let sentence = context.sentence

        // Parse each vital. nil means "no match in this sentence".
        let newHR = matchHeartRate(in: sentence)
        let newBP = matchBloodPressure(in: sentence)
        let newSpO2 = matchSpO2(in: sentence)
        let newRR = matchRespiratoryRate(in: sentence)

        // Mirror Python: RR is only recorded if not already set. (state.py:817)
        let rrToWrite: Int? = state.vitals.rr ?? newRR

        // No-op short-circuit: if no field changed, return state unchanged so
        // the engine can detect no-progress passes cheaply.
        if newHR == nil && newBP == nil && newSpO2 == nil &&
            (newRR == nil || state.vitals.rr != nil) {
            return state
        }

        var updated = state
        // Re-build Vitals so range validation runs (per Vitals.swift contract).
        updated.vitals = Vitals(
            hr: newHR ?? state.vitals.hr,
            bp: newBP ?? state.vitals.bp,
            spo2: newSpO2 ?? state.vitals.spo2,
            rr: rrToWrite,
            gcs: state.vitals.gcs,
            temperatureCelsius: state.vitals.temperatureCelsius,
            capillaryRefillSeconds: state.vitals.capillaryRefillSeconds
        )
        return updated
    }

    // MARK: - Per-vital matchers

    private func matchHeartRate(in text: String) -> Int? {
        return firstIntCapture(text, regex: hrRegex, group: 1)
    }

    private func matchBloodPressure(in text: String) -> BloodPressure? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let m = bpRegex.firstMatch(
            in: text, options: [], range: fullRange) else {
            return nil
        }
        guard m.numberOfRanges >= 3 else { return nil }
        let sysRange = m.range(at: 1)
        let diaRange = m.range(at: 2)
        guard sysRange.location != NSNotFound,
              diaRange.location != NSNotFound,
              let sys = Int(nsText.substring(with: sysRange)),
              let dia = Int(nsText.substring(with: diaRange)) else {
            return nil
        }

        // Group 3 is the optional palpated marker.
        var palpated = false
        if m.numberOfRanges >= 4 {
            let palpRange = m.range(at: 3)
            if palpRange.location != NSNotFound {
                let token = nsText.substring(with: palpRange).lowercased()
                // Any non-empty match for the optional group means palpated.
                palpated = !token.isEmpty
            }
        }

        return BloodPressure(systolic: sys, diastolic: dia, palpated: palpated)
    }

    private func matchSpO2(in text: String) -> Int? {
        return firstIntCapture(text, regex: spo2Regex, group: 1)
    }

    private func matchRespiratoryRate(in text: String) -> Int? {
        return firstIntCapture(text, regex: rrRegex, group: 1)
    }

    // MARK: - Helpers

    /// Run `regex` against `text`, return the integer value of capture group
    /// `group` from the first match (or nil if no match / not parseable).
    private func firstIntCapture(
        _ text: String, regex: NSRegularExpression, group: Int
    ) -> Int? {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let m = regex.firstMatch(
            in: text, options: [], range: fullRange) else {
            return nil
        }
        guard m.numberOfRanges > group else { return nil }
        let r = m.range(at: group)
        guard r.location != NSNotFound else { return nil }
        return Int(nsText.substring(with: r))
    }
}
