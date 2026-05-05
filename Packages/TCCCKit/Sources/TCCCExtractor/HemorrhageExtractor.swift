// HemorrhageExtractor
//
// Faithful Swift port of `_extract_hemorrhage` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 579–661) — the M of MARCH.
//
// Source-of-truth Python pattern definitions live around lines 361–387 inside
// `_compile_patterns`. The extractor mirrors the same dispatch:
//
//   1. Negative-bleeding pre-pass: if the text contains "no bleeding",
//      "no hemorrhage", etc., set hemorrhage_assessed but do NOT set
//      hemorrhage_identified.
//   2. Positive-bleeding pass: if the text contains "bleed/blood/hemorrhag"
//      AND it is NOT in a negative context, mark identified + assessed.
//   3. Location pass: only run if a hemorrhage CONTEXT word is present
//      (bleed/blood/hemorrhag/wound/injury/...). Patterns are tried in order:
//      bilateral first, then sided, then general body parts.
//   4. Tourniquet detection (with negation pre-check via tourniquet_negative).
//   5. Pressure-dressing detection.
//   6. "Controlled" / "stopped" detection.
//
// Deviation from Python: this Swift port respects `context.isNegated` only as
// a signal of last resort. The Python code does NOT short-circuit on
// `has_negated_finding(text, ...)` for hemorrhage — it relies on the
// dedicated `negative` regex above. We mirror that exactly to avoid breaking
// the scenario fixture assertions (esp. scenario 4, which has both "no
// external bleeding" AND a femur fracture where injuries[] still gets
// populated downstream).
//
// Foundation only.

import Foundation
import TCCCDomain

public struct HemorrhageExtractor: ExtractorPass {

    // MARK: - Compiled patterns

    private let identified: NSRegularExpression
    private let negative: NSRegularExpression
    private let bilateralLowerExtremity: NSRegularExpression
    private let bothLegsArms: NSRegularExpression
    private let sidedThighLegArm: NSRegularExpression
    private let generalBodyPart: NSRegularExpression
    private let tourniquet: NSRegularExpression
    private let tourniquetNegative: NSRegularExpression
    private let tourniquetReposition: NSRegularExpression
    private let controlled: NSRegularExpression
    private let pressureDressing: NSRegularExpression

    public init() {
        // Verbatim from state.py:362–387.
        self.identified = try! NSRegularExpression(
            pattern: "bleed|blood|hemorrhag", options: [.caseInsensitive])

        self.negative = try! NSRegularExpression(
            pattern:
                "no\\s+(external\\s+)?bleed|no\\s+hemorrhag|no\\s+massive\\s+hemorrhag|" +
                "no\\s+significant\\s+bleed|no\\s+active\\s+bleed|" +
                "no\\s+obvious\\s+bleed|no\\s+visible\\s+bleed|" +
                "not\\s+bleed|isn't\\s+bleed|no\\s+blood",
            options: [.caseInsensitive])

        // Location patterns, in priority order. We keep three NSRegularExpression
        // instances so we can run them in the same order Python does.
        self.bilateralLowerExtremity = try! NSRegularExpression(
            pattern: "bilateral\\s*(lower\\s*)?(thigh|leg|arm|extremit\\w*)",
            options: [.caseInsensitive])

        self.bothLegsArms = try! NSRegularExpression(
            pattern: "both\\s*(legs?|arms?|thighs?|extremit\\w*)",
            options: [.caseInsensitive])

        self.sidedThighLegArm = try! NSRegularExpression(
            pattern: "(right|left)\\s*(upper\\s*)?(thigh|leg|arm|forearm|extremit\\w*)",
            options: [.caseInsensitive])

        self.generalBodyPart = try! NSRegularExpression(
            pattern: "(thigh|leg|arm|forearm|chest|abdomen)\\s*(area|wound)?",
            options: [.caseInsensitive])

        self.tourniquet = try! NSRegularExpression(
            pattern: "tourniquet|tq|cat\\s*tourniquet|cat\\s*tonic|\\btonic\\b",
            options: [.caseInsensitive])

        self.tourniquetNegative = try! NSRegularExpression(
            pattern: "no\\s+(?:tonic|tourniquet)\\s+needed|not?\\s+(?:tonic|tourniquet)|tonicaine",
            options: [.caseInsensitive])

        // 2026 §6 TQ reposition vocabulary — explicit conversion event.
        // Per march_paws_vocabulary_2026.json MARCH.C.tourniquet reposition:
        // "apply a second tourniquet directly to the skin 2-3 inches above
        // the bleeding site, then loosening the first." Replaces 2024
        // "replace tourniquet" language but the older verb is kept for
        // backward compatibility in the alternation below.
        self.tourniquetReposition = try! NSRegularExpression(
            pattern:
                "reposition(?:ing)?\\s+(?:the\\s+)?tourniquet|" +
                "reposition(?:ing)?\\s+(?:the\\s+)?tq|" +
                "(?:applied?|apply)\\s+a\\s+second\\s+(?:tourniquet|tq)|" +
                "directly\\s+to\\s+the\\s+skin\\s+2-?3\\s+inches\\s+above|" +
                "loosen(?:ed|ing)?\\s+the\\s+(?:first|original)\\s+(?:tourniquet|tq)|" +
                "replac(?:e|ing)\\s+(?:the\\s+)?tourniquet",
            options: [.caseInsensitive])

        self.controlled = try! NSRegularExpression(
            pattern: "controlled|stopped|no\\s*(more\\s*)?bleed",
            options: [.caseInsensitive])

        self.pressureDressing = try! NSRegularExpression(
            pattern: "pressure\\s*dressing|dressing\\s*applied|bandage",
            options: [.caseInsensitive])
    }

    // MARK: - Apply

    public func apply(_ state: PatientState, context: ExtractionContext) -> PatientState {
        var s = state
        var march = s.march
        let text = context.sentence
        let hasNegativeBleeding = matches(negative, text)
        let hasPositiveBleeding = matches(identified, text)

        // 1. Negative bleeding pre-pass.
        if hasNegativeBleeding {
            march.hemorrhageAssessed = true
        }

        // 2. Positive bleeding indicators.
        if hasPositiveBleeding && !hasNegativeBleeding {
            march.hemorrhageIdentified = true
            march.hemorrhageAssessed = true
        }

        // 3. Location pass. Only run when the sentence has a hemorrhage
        //    context word — mirrors `has_hemorrhage_context` in Python.
        let lower = text.lowercased()
        let contextWords = [
            "bleed", "blood", "hemorrhag", "wound", "injury", "injur",
            "gsw", "lacerat", "tourniquet", "tonic", "tq",
        ]
        let hasHemorrhageContext = contextWords.contains { lower.contains($0) }

        if hasHemorrhageContext {
            // Try the four patterns in Python order; first match wins.
            if let loc = extractBilateralLowerExtremity(text) {
                march.hemorrhageIdentified = true
                march.hemorrhageLocation = mergeLocation(
                    new: loc, current: march.hemorrhageLocation)
            } else if let loc = extractBothLegsArms(text) {
                march.hemorrhageIdentified = true
                march.hemorrhageLocation = mergeLocation(
                    new: loc, current: march.hemorrhageLocation)
            } else if let loc = extractSidedThighLegArm(text) {
                march.hemorrhageIdentified = true
                march.hemorrhageLocation = mergeLocation(
                    new: loc, current: march.hemorrhageLocation)
            } else if let loc = extractGeneralBodyPart(text) {
                march.hemorrhageIdentified = true
                march.hemorrhageLocation = mergeLocation(
                    new: loc, current: march.hemorrhageLocation)
            }
        }

        // 4. Tourniquet detection (with negation pre-check).
        let hasTQ = matches(tourniquet, text)
        let hasTQNegated = matches(tourniquetNegative, text)
        if hasTQ && !hasTQNegated {
            if let location = march.hemorrhageLocation {
                march.hemorrhageIntervention = "Tourniquet applied (\(location))"
            } else {
                march.hemorrhageIntervention = "Tourniquet applied"
            }
            // Append to interventions if not already present.
            let existingDesc = s.interventions.map { $0.description.lowercased() }
                .joined(separator: "|")
            if !existingDesc.contains("tourniquet") {
                s.interventions.append(Intervention(
                    timestamp: context.timestamp,
                    kind: .tourniquet,
                    description: "Tourniquet applied"))
            }
        }

        // 4b. 2026 §6 TQ reposition / conversion event.
        // Emits a distinct .tourniquetConversion intervention so the
        // ASM/CLS scope warning (2026 §6, sprint 2.5) and downstream
        // documentation can distinguish initial application from
        // conversion. Independent of the tourniquetNegative gate; even if
        // the sentence says "no new tourniquet needed", a "loosened the
        // first" mention is still a conversion event.
        if matches(tourniquetReposition, text) {
            let existingDesc = s.interventions.map { $0.description.lowercased() }
                .joined(separator: "|")
            if !existingDesc.contains("tourniquet repositioned") {
                s.interventions.append(Intervention(
                    timestamp: context.timestamp,
                    kind: .tourniquetConversion,
                    description: "Tourniquet repositioned"))
            }
        }

        // 5. Pressure dressing detection.
        if matches(pressureDressing, text) {
            if march.hemorrhageIntervention == nil {
                march.hemorrhageIntervention = "Pressure dressing applied"
            }
            let existingDesc = s.interventions.map { $0.description.lowercased() }
                .joined(separator: "|")
            if !existingDesc.contains("pressure dressing") {
                s.interventions.append(Intervention(
                    timestamp: context.timestamp,
                    kind: .pressureDressing,
                    description: "Pressure dressing applied"))
            }
        }

        // 6. Controlled.
        if matches(controlled, text) {
            march.hemorrhageEffective = true
        }

        s.march = march
        return s
    }

    // MARK: - Location extraction helpers
    //
    // Each helper mirrors the corresponding lambda in Python's
    // `hemorrhage_patterns["location"]` list. Returned strings match Python's
    // formatting exactly so downstream tests (which assert lowercase
    // substrings) remain valid.

    private func extractBilateralLowerExtremity(_ text: String) -> String? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let m = bilateralLowerExtremity.firstMatch(
            in: text, options: [], range: range) else { return nil }
        // Python: lambda m: f"bilateral {m.group(2) if m.group(2) else 'extremity'}"
        let g2 = group(m, at: 2, in: nsText)
        let part = g2.isEmpty ? "extremity" : g2
        return "bilateral \(part)".lowercased().trimmingCharacters(in: .whitespaces)
    }

    private func extractBothLegsArms(_ text: String) -> String? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let m = bothLegsArms.firstMatch(
            in: text, options: [], range: range) else { return nil }
        // Python: lambda m: f"bilateral {m.group(1)}"
        let g1 = group(m, at: 1, in: nsText)
        return "bilateral \(g1)".lowercased().trimmingCharacters(in: .whitespaces)
    }

    private func extractSidedThighLegArm(_ text: String) -> String? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let m = sidedThighLegArm.firstMatch(
            in: text, options: [], range: range) else { return nil }
        // Python: lambda m: m.group(0) — preserves "right upper thigh" etc.
        let g0 = group(m, at: 0, in: nsText)
        return g0.lowercased().trimmingCharacters(in: .whitespaces)
    }

    private func extractGeneralBodyPart(_ text: String) -> String? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let m = generalBodyPart.firstMatch(
            in: text, options: [], range: range) else { return nil }
        // Python: lambda m: m.group(1)
        let g1 = group(m, at: 1, in: nsText)
        return g1.lowercased().trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Location merging
    //
    // Mirrors the right + left → bilateral inference and the redundancy guard
    // that Python's `_extract_hemorrhage` performs (state.py:610–637).

    private func mergeLocation(new: String, current: String?) -> String {
        guard let current = current else { return new }
        let cur = current.lowercased()

        // Skip if the new location is redundant with the existing one.
        if isRedundantLocation(newLocation: new, current: cur) {
            return current
        }

        // Detect bilateral from right + left.
        if !cur.contains("bilateral") {
            let hasRight = cur.contains("right") || new.contains("right")
            let hasLeft = cur.contains("left") || new.contains("left")
            if hasRight && hasLeft {
                let parts = ["leg", "thigh", "arm", "forearm", "extremity"]
                if let bodyPart = parts.first(where: { cur.contains($0) || new.contains($0) }) {
                    return "bilateral \(bodyPart)s"
                }
                return "bilateral lower extremities"
            }
            if !cur.contains(new) {
                return "\(current), \(new)"
            }
        }
        return current
    }

    /// Mirrors `_is_redundant_location` from state.py:1049–1094.
    private func isRedundantLocation(newLocation: String, current: String) -> Bool {
        let newLower = newLocation.lowercased()
        let curLower = current.lowercased()

        // Direct containment check.
        if curLower.contains(newLower) { return true }

        let sides = ["right", "left", "bilateral"]
        let bodyParts = ["thigh", "leg", "arm", "forearm", "extremity", "extremities"]

        func extractComponents(_ loc: String) -> (side: String?, part: String?) {
            let side = sides.first(where: { loc.contains($0) })
            let part = bodyParts.first(where: { loc.contains($0) })
            return (side, part)
        }

        let (newSide, newPart) = extractComponents(newLower)
        let (curSide, curPart) = extractComponents(curLower)

        if let newSide = newSide, let curSide = curSide, newSide == curSide,
           let newPart = newPart, let curPart = curPart {
            if newPart == curPart { return true }
            // "thigh" is part of "leg" anatomically.
            if (newPart == "thigh" && curPart == "leg") ||
               (newPart == "leg" && curPart == "thigh") {
                return true
            }
        }
        return false
    }

    // MARK: - Regex helpers

    private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let nsText = text as NSString
        let r = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: r) != nil
    }

    private func group(
        _ match: NSTextCheckingResult, at index: Int, in nsText: NSString
    ) -> String {
        guard index < match.numberOfRanges else { return "" }
        let r = match.range(at: index)
        if r.location == NSNotFound { return "" }
        return nsText.substring(with: r)
    }
}
