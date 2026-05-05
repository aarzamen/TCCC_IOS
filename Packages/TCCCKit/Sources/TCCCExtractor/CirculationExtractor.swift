// CirculationExtractor
//
// Faithful Swift port of `_extract_circulation` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 730–764), using the
// `circulation_patterns` table at lines 410–424.
//
// Behaviour preserved verbatim from the Python source:
//
//   1. Pulse pattern table is iterated in order; first match wins. The
//      "radial pulse (is) present/strong/..." form yields "radial <quality>";
//      the bare "<quality> pulse" form yields "<quality> radial"; the
//      generic "pulse (is) present/..." form yields just the quality.
//   2. Skin-sign pattern table is iterated in order; first match with a
//      non-empty extracted descriptor wins.
//   3. IV access is checked with a `\biv\b` word-boundary pattern (P1 #6 fix
//      so that "five", "give", "arrive" do NOT trigger an IV finding). When
//      matched, sets `circulationIntervention` to "IV access" and appends
//      "IV access established" to interventions if not already present.
//   4. IO access only checked if IV did not match (Python uses `if/elif`).
//
// The wider engine sets `ExtractionContext.isNegated` per sentence; when the
// flag is set, this extractor skips positive findings (pulse, skin signs,
// IV/IO interventions), mirroring the discipline described in the lane brief.
//
// Foundation only.

import Foundation
import TCCCDomain

/// Extracts circulation findings: pulse status, skin signs, and IV/IO access.
/// Updates `state.march.pulseStatus`, `state.march.skinSigns`,
/// `state.march.circulationIntervention`, and appends to `state.interventions`
/// when IV or IO access is detected.
public struct CirculationExtractor: ExtractorPass {

    private struct CaptureRule {
        let regex: NSRegularExpression
        /// Returns the descriptor string given the captured groups, or `nil`
        /// to signal no descriptor for this match.
        let extract: @Sendable (NSTextCheckingResult, NSString) -> String?
    }

    private let pulseRules: [CaptureRule]
    private let skinRules: [CaptureRule]
    private let ivRegex: NSRegularExpression
    private let ioRegex: NSRegularExpression
    private let calciumRegex: NSRegularExpression

    public init() {
        // (re.compile(r"radial\s*pulse\s*(is\s*)?(present|strong|weak|absent|palpable)", re.I),
        //  lambda m: f"radial {m.group(2) if m.group(2) else 'present'}")
        let radialPulse = try! NSRegularExpression(
            pattern: "radial\\s*pulse\\s*(is\\s*)?(present|strong|weak|absent|palpable)",
            options: [.caseInsensitive]
        )
        // (re.compile(r"(strong|weak|absent|thready)\s*(radial\s*)?pulse", re.I),
        //  lambda m: f"{m.group(1)} radial")
        let qualityPulse = try! NSRegularExpression(
            pattern: "(strong|weak|absent|thready)\\s*(radial\\s*)?pulse",
            options: [.caseInsensitive]
        )
        // (re.compile(r"pulse\s*(is\s*)?(present|strong|weak|absent)", re.I),
        //  lambda m: m.group(2) if m.group(2) else "present")
        let bareQualityPulse = try! NSRegularExpression(
            pattern: "pulse\\s*(is\\s*)?(present|strong|weak|absent)",
            options: [.caseInsensitive]
        )

        self.pulseRules = [
            CaptureRule(regex: radialPulse) { match, ns in
                guard match.numberOfRanges >= 3 else { return "radial present" }
                let g2 = match.range(at: 2)
                if g2.location != NSNotFound, g2.length > 0 {
                    return "radial \(ns.substring(with: g2).lowercased())"
                }
                return "radial present"
            },
            CaptureRule(regex: qualityPulse) { match, ns in
                guard match.numberOfRanges >= 2 else { return nil }
                let g1 = match.range(at: 1)
                if g1.location != NSNotFound, g1.length > 0 {
                    return "\(ns.substring(with: g1).lowercased()) radial"
                }
                return nil
            },
            CaptureRule(regex: bareQualityPulse) { match, ns in
                guard match.numberOfRanges >= 3 else { return "present" }
                let g2 = match.range(at: 2)
                if g2.location != NSNotFound, g2.length > 0 {
                    return ns.substring(with: g2).lowercased()
                }
                return "present"
            },
        ]

        // (re.compile(r"skin\s*(is\s*)?(warm|cool|cold|pale|clammy|diaphoretic|dry)", re.I),
        //  lambda m: m.group(2) if m.group(2) else "")
        let bareSkin = try! NSRegularExpression(
            pattern: "skin\\s*(is\\s*)?(warm|cool|cold|pale|clammy|diaphoretic|dry)",
            options: [.caseInsensitive]
        )
        // (re.compile(r"(warm|cool|cold)\s*(and\s*)?(dry|clammy|diaphoretic)", re.I),
        //  lambda m: f"{m.group(1)} {m.group(3)}")
        let twoWordSkin = try! NSRegularExpression(
            pattern: "(warm|cool|cold)\\s*(and\\s*)?(dry|clammy|diaphoretic)",
            options: [.caseInsensitive]
        )

        self.skinRules = [
            CaptureRule(regex: bareSkin) { match, ns in
                guard match.numberOfRanges >= 3 else { return nil }
                let g2 = match.range(at: 2)
                if g2.location != NSNotFound, g2.length > 0 {
                    let val = ns.substring(with: g2).lowercased()
                    return val.isEmpty ? nil : val
                }
                return nil
            },
            CaptureRule(regex: twoWordSkin) { match, ns in
                guard match.numberOfRanges >= 4 else { return nil }
                let g1 = match.range(at: 1)
                let g3 = match.range(at: 3)
                guard g1.location != NSNotFound, g1.length > 0,
                      g3.location != NSNotFound, g3.length > 0 else { return nil }
                let a = ns.substring(with: g1).lowercased()
                let b = ns.substring(with: g3).lowercased()
                return "\(a) \(b)"
            },
        ]

        // P1 #6: \biv\b word boundary so "five", "give", "arrive" don't trigger.
        self.ivRegex = try! NSRegularExpression(
            pattern: "\\biv\\b|intravenous|saline\\s*lock|eighteen\\s*gauge|18\\s*gauge|starting\\s+an?\\s+(?:iv|line)",
            options: [.caseInsensitive]
        )
        self.ioRegex = try! NSRegularExpression(
            pattern: "\\bio\\b|intraosseous",
            options: [.caseInsensitive]
        )
        // 2026 §6 calcium administration after transfusion.
        // Per march_paws_vocabulary_2026.json MARCH.C.calcium administration
        // after transfusion: "1 g calcium IV/IO" / "30 ml of 10% calcium
        // gluconate" / "10 ml of 10% calcium chloride" given after first
        // transfused product.
        self.calciumRegex = try! NSRegularExpression(
            pattern:
                "calcium\\s+gluconate|calcium\\s+chloride|" +
                "1\\s*g(?:ram)?\\s+calcium|" +
                "calcium\\s+(?:iv|io)|" +
                "30\\s*ml\\s+of\\s+10%?\\s+calcium\\s+gluconate|" +
                "10\\s*ml\\s+of\\s+10%?\\s+calcium\\s+chloride",
            options: [.caseInsensitive]
        )
    }

    public func apply(_ state: PatientState, context: ExtractionContext) -> PatientState {
        var s = state
        let text = context.sentence
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // 1. Pulse — first matching rule wins. Skip when sentence is negated.
        if !context.isNegated {
            for rule in pulseRules {
                if let match = rule.regex.firstMatch(in: text, options: [], range: fullRange) {
                    if let descriptor = rule.extract(match, nsText) {
                        s.march.pulseStatus = descriptor
                    }
                    break
                }
            }
        }

        // 2. Skin signs — first matching rule with a non-empty descriptor wins.
        // Python iterates and only assigns when the lambda returns truthy.
        if !context.isNegated {
            for rule in skinRules {
                if let match = rule.regex.firstMatch(in: text, options: [], range: fullRange) {
                    if let descriptor = rule.extract(match, nsText), !descriptor.isEmpty {
                        s.march.skinSigns = descriptor
                        break
                    }
                    // If the closure returned nil, mirror Python's "skip this match,
                    // continue to next rule".
                }
            }
        }

        // 3. IV / IO access — mutually exclusive (Python `if/elif`).
        if !context.isNegated {
            if ivRegex.firstMatch(in: text, options: [], range: fullRange) != nil {
                s.march.circulationIntervention = "IV access"
                // Python: `if "IV" not in str(patient.interventions)` — case-sensitive,
                // checks for the substring "IV" (uppercase). Mirror that exactly.
                if !s.interventions.contains(where: { $0.description.contains("IV") }) {
                    s.interventions.append(
                        Intervention(
                            timestamp: context.timestamp,
                            kind: .ivAccess,
                            description: "IV access established"
                        )
                    )
                }
            } else if ioRegex.firstMatch(in: text, options: [], range: fullRange) != nil {
                s.march.circulationIntervention = "IO access"
                // Python: `if "IO" not in str(patient.interventions)` — same pattern.
                if !s.interventions.contains(where: { $0.description.contains("IO") }) {
                    s.interventions.append(
                        Intervention(
                            timestamp: context.timestamp,
                            kind: .ioAccess,
                            description: "IO access established"
                        )
                    )
                }
            }

            // 4. 2026 §6 calcium-after-transfusion.
            if calciumRegex.firstMatch(in: text, options: [], range: fullRange) != nil {
                let existing = s.interventions.map { $0.description.lowercased() }
                    .joined(separator: "|")
                if !existing.contains("calcium") {
                    s.interventions.append(
                        Intervention(
                            timestamp: context.timestamp,
                            kind: .medication,
                            description: "Calcium administered (post-transfusion)"
                        )
                    )
                }
            }
        }

        return s
    }
}
