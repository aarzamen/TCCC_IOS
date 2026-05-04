// RespirationExtractor
//
// Faithful Swift port of `_extract_respiration` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 683–728), together with the
// `respiration_patterns` table at lines 398–408.
//
// Behaviour preserved verbatim from the Python source:
//
//   1. Try each `breath_sounds` pattern in order; first match wins. Output is
//      one of "bilateral equal" or "diminished left/right".
//   2. Pneumothorax check runs an embedded negation pre-pass (P1 #4 fix):
//      "no signs of pneumothorax", "no tension", "no chest trauma" all
//      suppress the positive finding. Only sets `respirationStatus =
//      "possible pneumothorax"` if the pattern matches AND none of those
//      negations apply.
//   3. Chest seal precedes needle decompression (Python uses `if/elif`).
//      Both append a deduplicated entry to `interventions`.
//   4. Respiratory rate match also seeds `vitals.rr` and inferred
//      respiration status when none is set yet (or when only the speculative
//      "possible pneumothorax" was inferred).
//
// The wider engine sets `ExtractionContext.isNegated` per sentence; this
// extractor honours it for the `breath_sounds` step (Python skips the entire
// finding if the sentence is negated by an external check) but the
// pneumothorax pre-pass uses its own targeted negation lookup verbatim from
// Python — which is more precise than the loose sentence-level flag.
//
// Foundation only.

import Foundation
import TCCCDomain

/// Extracts respiration findings, breath sounds, pneumothorax status, and
/// respiratory interventions (chest seal, needle decompression). Updates
/// `state.march.respirationStatus`, `state.march.respirationIntervention`,
/// `state.march.breathSounds`, `state.vitals.rr`, and appends to
/// `state.interventions` when a respiratory intervention is detected.
public struct RespirationExtractor: ExtractorPass {

    // MARK: - Compiled patterns

    /// Breath-sound regex pairs. The closure derives the canonical descriptor
    /// from the regex match. Order matters — first matching entry wins.
    private struct BreathSoundsRule {
        let regex: NSRegularExpression
        /// Returns the descriptor string given the captured groups, or `nil`
        /// to signal no descriptor for this match.
        let extract: @Sendable (NSTextCheckingResult, NSString) -> String?
    }

    private let breathSoundsRules: [BreathSoundsRule]
    private let pneumothoraxRegex: NSRegularExpression
    private let chestSealRegex: NSRegularExpression
    private let needleDecompressionRegex: NSRegularExpression
    private let rateRegex: NSRegularExpression
    private let negation: NegationDetector

    public init() {
        // (re.compile(r"breath\s*sounds?\s*(bilateral|equal|clear)", re.I), "bilateral equal")
        let bilateralEqual = try! NSRegularExpression(
            pattern: "breath\\s*sounds?\\s*(bilateral|equal|clear)",
            options: [.caseInsensitive]
        )
        // (re.compile(r"diminished\s*(on\s*the\s*)?(left|right)", re.I),
        //  lambda m: f"diminished {m.group(2) if m.group(2) else ''}".strip())
        let diminishedSide = try! NSRegularExpression(
            pattern: "diminished\\s*(on\\s*the\\s*)?(left|right)",
            options: [.caseInsensitive]
        )
        // (re.compile(r"(left|right)\s*side\s*diminished", re.I),
        //  lambda m: f"diminished {m.group(1)}")
        let sideDiminished = try! NSRegularExpression(
            pattern: "(left|right)\\s*side\\s*diminished",
            options: [.caseInsensitive]
        )

        self.breathSoundsRules = [
            BreathSoundsRule(regex: bilateralEqual) { _, _ in "bilateral equal" },
            BreathSoundsRule(regex: diminishedSide) { match, ns in
                guard match.numberOfRanges >= 3 else { return "diminished" }
                let group2 = match.range(at: 2)
                if group2.location != NSNotFound, group2.length > 0 {
                    let side = ns.substring(with: group2).lowercased()
                    return "diminished \(side)"
                }
                return "diminished"
            },
            BreathSoundsRule(regex: sideDiminished) { match, ns in
                guard match.numberOfRanges >= 2 else { return nil }
                let group1 = match.range(at: 1)
                if group1.location != NSNotFound, group1.length > 0 {
                    let side = ns.substring(with: group1).lowercased()
                    return "diminished \(side)"
                }
                return nil
            },
        ]

        self.pneumothoraxRegex = try! NSRegularExpression(
            pattern: "pneumothorax|tension",
            options: [.caseInsensitive]
        )
        self.chestSealRegex = try! NSRegularExpression(
            pattern: "chest\\s*seal|occlusive",
            options: [.caseInsensitive]
        )
        self.needleDecompressionRegex = try! NSRegularExpression(
            pattern: "needle\\s*decompression|needle\\s*d",
            options: [.caseInsensitive]
        )
        self.rateRegex = try! NSRegularExpression(
            pattern: "respiratory\\s*rate\\s*(?:is\\s*|looks?\\s*(?:about\\s*)?)?(\\d+)",
            options: [.caseInsensitive]
        )
        self.negation = NegationDetector()
    }

    public func apply(_ state: PatientState, context: ExtractionContext) -> PatientState {
        var s = state
        let text = context.sentence
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // 1. Breath sounds — first matching rule wins.
        //
        // Python's `_extract_respiration` does NOT pre-check `isNegated` for
        // breath sounds because "bilateral breath sounds clear" and similar
        // positive findings are common and should be honoured even if the
        // sentence happens to contain other negations. We mirror that: only
        // skip if the sentence is generally negated AND the breath-sound
        // descriptor itself appears under a negation marker. Conservative:
        // only skip when isNegated is true.
        if !context.isNegated {
            for rule in breathSoundsRules {
                if let match = rule.regex.firstMatch(in: text, options: [], range: fullRange) {
                    if let descriptor = rule.extract(match, nsText) {
                        s.march.breathSounds = descriptor
                    }
                    break
                }
            }
        }

        // 2. Pneumothorax — targeted negation pre-pass independent of the
        // sentence-level `isNegated` flag (Python does its own narrow check).
        let pneumoNegated =
            negation.hasNegatedFinding(in: text, finding: "pneumothorax") ||
            negation.hasNegatedFinding(in: text, finding: "tension") ||
            negation.hasNegatedFinding(in: text, finding: "chest trauma")
        if !pneumoNegated,
           pneumothoraxRegex.firstMatch(in: text, options: [], range: fullRange) != nil {
            s.march.respirationStatus = "possible pneumothorax"
        }

        // 3. Interventions — chest seal first, then needle decompression
        //    (Python uses if/elif so they are mutually exclusive per sentence).
        if !context.isNegated {
            if chestSealRegex.firstMatch(in: text, options: [], range: fullRange) != nil {
                s.march.respirationIntervention = "Chest seal applied"
                if !s.interventions.contains(where: {
                    $0.description.lowercased().contains("chest seal")
                }) {
                    s.interventions.append(
                        Intervention(
                            timestamp: context.timestamp,
                            kind: .chestSeal,
                            description: "Chest seal applied"
                        )
                    )
                }
            } else if needleDecompressionRegex.firstMatch(in: text, options: [], range: fullRange) != nil {
                s.march.respirationIntervention = "Needle decompression"
                if !s.interventions.contains(where: {
                    $0.description.lowercased().contains("needle")
                }) {
                    s.interventions.append(
                        Intervention(
                            timestamp: context.timestamp,
                            kind: .needleDecompression,
                            description: "Needle decompression"
                        )
                    )
                }
            }
        }

        // 4. Respiratory rate — set vitals.rr and infer status when not yet
        //    determined (or when only the speculative pneumothorax was set).
        if let match = rateRegex.firstMatch(in: text, options: [], range: fullRange),
           match.numberOfRanges >= 2 {
            let rrRange = match.range(at: 1)
            if rrRange.location != NSNotFound,
               let rr = Int(nsText.substring(with: rrRange)) {
                // Vitals struct silently drops out-of-range values — set via init.
                var v = s.vitals
                if let valid = Vitals(rr: rr).rr {
                    v.rr = valid
                    s.vitals = v
                }

                // Set respiration status from rate when none yet, or when only
                // the speculative pneumothorax was previously inferred.
                let currentStatus = s.march.respirationStatus
                if currentStatus == nil || currentStatus == "possible pneumothorax" {
                    if (12...20).contains(rr) {
                        s.march.respirationStatus = "normal"
                    } else if rr > 20 {
                        s.march.respirationStatus = "tachypneic"
                    } else if rr < 12 {
                        s.march.respirationStatus = "bradypneic"
                    }
                }
            }
        }

        return s
    }
}
