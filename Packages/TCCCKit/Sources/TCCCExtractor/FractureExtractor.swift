// FractureExtractor
//
// Faithful Swift port of `_extract_fractures` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 857–896), using the
// `fracture_patterns` table at lines 459–469.
//
// Behaviour preserved verbatim from the Python source:
//
//   1. The top-level "fracture" pattern gates whether the location patterns
//      are even tried. If "fracture", "broken bone/leg/arm", or "fx" doesn't
//      appear in the sentence, we skip to splint detection.
//   2. The location pattern table is iterated in order. The FIRST matching
//      regex wins, even if it would produce an identical descriptor as a
//      later one (Python uses `break` after the first match). Note: the
//      table includes both `(right|left)?\s*femur fracture` and a bare
//      `femur fracture` — the parameterised one wins by being listed first.
//   3. The descriptor is appended to `injuries` (capitalised) only if no
//      existing injury already contains it (case-insensitive substring).
//   4. Femur or thigh fractures additionally seed
//      `march.hemorrhageLocation` ("right thigh (femur fracture)") since
//      femur fractures carry significant internal-bleeding risk. If a
//      hemorrhage location already exists and doesn't already mention
//      "femur", append "(femur fracture)" to it.
//   5. Splinting is detected with a separate top-level pattern (independent
//      of the fracture pattern). The descriptor is "Traction splint (Sager)"
//      for sager/traction splints, "SAM splint" for SAM, otherwise the
//      generic "Splint applied". Appended to interventions if not already
//      present (case-insensitive substring check).
//
// Splinting belongs to the fracture extractor in Python (NOT to PAWS), per
// the function definition. Lane B owns it accordingly.
//
// Foundation only.

import Foundation
import TCCCDomain

/// Extracts fractures and splinting interventions. Updates `state.injuries`
/// with the fracture descriptor, may seed `state.march.hemorrhageLocation`
/// for femur/thigh fractures (internal-bleeding risk), and appends to
/// `state.interventions` when a splint is detected.
public struct FractureExtractor: ExtractorPass {

    private struct LocationRule {
        let regex: NSRegularExpression
        /// Returns the canonical fracture descriptor (lowercase, e.g.
        /// "right femur fracture") given the captured groups.
        let extract: @Sendable (NSTextCheckingResult, NSString) -> String
    }

    private let fractureRegex: NSRegularExpression
    private let locationRules: [LocationRule]
    private let splintRegex: NSRegularExpression
    private let sagerRegex: NSRegularExpression
    private let samRegex: NSRegularExpression

    public init() {
        // re.compile(r"fracture|broken\s*(bone|leg|arm)|fx", re.I)
        self.fractureRegex = try! NSRegularExpression(
            pattern: "fracture|broken\\s*(bone|leg|arm)|fx",
            options: [.caseInsensitive]
        )

        // (re.compile(r"(right|left)?\s*(femur|thigh|hip)\s*fracture", re.I),
        //  lambda m: f"{m.group(1) or ''} femur fracture".strip())
        let femurOrThigh = try! NSRegularExpression(
            pattern: "(right|left)?\\s*(femur|thigh|hip)\\s*fracture",
            options: [.caseInsensitive]
        )
        // (re.compile(r"femur\s*fracture", re.I), "femur fracture")
        let bareFemur = try! NSRegularExpression(
            pattern: "femur\\s*fracture",
            options: [.caseInsensitive]
        )
        // (re.compile(r"(right|left)?\s*(tibia|lower\s*leg|ankle)\s*fracture", re.I),
        //  lambda m: f"{m.group(1) or ''} lower leg fracture".strip())
        let lowerLeg = try! NSRegularExpression(
            pattern: "(right|left)?\\s*(tibia|lower\\s*leg|ankle)\\s*fracture",
            options: [.caseInsensitive]
        )
        // (re.compile(r"(right|left)?\s*(arm|radius|ulna|wrist|elbow)\s*fracture", re.I),
        //  lambda m: f"{m.group(1) or ''} arm fracture".strip())
        let arm = try! NSRegularExpression(
            pattern: "(right|left)?\\s*(arm|radius|ulna|wrist|elbow)\\s*fracture",
            options: [.caseInsensitive]
        )

        self.locationRules = [
            LocationRule(regex: femurOrThigh) { match, ns in
                let side = Self.optionalGroup(match, group: 1, in: ns)
                return "\(side) femur fracture".trimmingCharacters(in: .whitespaces)
            },
            LocationRule(regex: bareFemur) { _, _ in "femur fracture" },
            LocationRule(regex: lowerLeg) { match, ns in
                let side = Self.optionalGroup(match, group: 1, in: ns)
                return "\(side) lower leg fracture".trimmingCharacters(in: .whitespaces)
            },
            LocationRule(regex: arm) { match, ns in
                let side = Self.optionalGroup(match, group: 1, in: ns)
                return "\(side) arm fracture".trimmingCharacters(in: .whitespaces)
            },
        ]

        // re.compile(r"splint|sager|traction\s*splint|sam\s*splint|immobili", re.I)
        self.splintRegex = try! NSRegularExpression(
            pattern: "splint|sager|traction\\s*splint|sam\\s*splint|immobili",
            options: [.caseInsensitive]
        )
        // re.search(r"sager|traction\s*splint", text, re.I)
        self.sagerRegex = try! NSRegularExpression(
            pattern: "sager|traction\\s*splint",
            options: [.caseInsensitive]
        )
        // re.search(r"sam\s*splint", text, re.I)
        self.samRegex = try! NSRegularExpression(
            pattern: "sam\\s*splint",
            options: [.caseInsensitive]
        )
    }

    public func apply(_ state: PatientState, context: ExtractionContext) -> PatientState {
        var s = state
        let text = context.sentence
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // 1+2. Fracture: only attempt location extraction if the gating
        // "fracture" pattern matches AND the sentence is not negated.
        // Python doesn't pre-check negation here, but the lane brief asks us
        // to respect the sentence-level isNegated flag for positive findings.
        if !context.isNegated,
           fractureRegex.firstMatch(in: text, options: [], range: fullRange) != nil {

            for rule in locationRules {
                guard let match = rule.regex.firstMatch(in: text, options: [], range: fullRange) else {
                    continue
                }
                let descriptor = rule.extract(match, nsText)
                let descLower = descriptor.lowercased()

                // 3. Append to injuries (capitalised) if no existing injury
                // already contains the descriptor (case-insensitive substring).
                if !s.injuries.contains(where: { $0.lowercased().contains(descLower) }) {
                    s.injuries.append(Self.capitalizeFirst(descriptor))
                }

                // 4. Femur/thigh: seed or annotate hemorrhage location.
                if descLower.contains("femur") || descLower.contains("thigh") {
                    if let existing = s.march.hemorrhageLocation {
                        if !existing.lowercased().contains("femur") {
                            s.march.hemorrhageLocation = "\(existing) (femur fracture)"
                        }
                    } else {
                        // Python hard-codes "right thigh (femur fracture)" here
                        // even when no side was detected. Mirror that quirk.
                        s.march.hemorrhageLocation = "right thigh (femur fracture)"
                    }
                }

                break
            }
        }

        // 5. Splinting — independent top-level check, also gated by negation.
        if !context.isNegated,
           splintRegex.firstMatch(in: text, options: [], range: fullRange) != nil {

            let splintType: String
            let kind: InterventionKind = .splint
            if sagerRegex.firstMatch(in: text, options: [], range: fullRange) != nil {
                splintType = "Traction splint (Sager)"
            } else if samRegex.firstMatch(in: text, options: [], range: fullRange) != nil {
                splintType = "SAM splint"
            } else {
                splintType = "Splint applied"
            }

            let splintLower = splintType.lowercased()
            if !s.interventions.contains(where: {
                $0.description.lowercased().contains(splintLower)
            }) {
                s.interventions.append(
                    Intervention(
                        timestamp: context.timestamp,
                        kind: kind,
                        description: splintType
                    )
                )
            }
        }

        return s
    }

    // MARK: - Helpers

    /// Returns the captured group as a lowercase string, or empty string if
    /// the group did not match. Mirrors Python's `m.group(N) or ''` idiom.
    private static func optionalGroup(
        _ match: NSTextCheckingResult,
        group: Int,
        in ns: NSString
    ) -> String {
        guard match.numberOfRanges > group else { return "" }
        let range = match.range(at: group)
        guard range.location != NSNotFound, range.length > 0 else { return "" }
        return ns.substring(with: range).lowercased()
    }

    /// Capitalises just the first character — mirrors Python's `str.capitalize()`
    /// closely enough for the descriptor strings we emit (which contain only
    /// lowercase ASCII words separated by spaces).
    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst().lowercased()
    }
}
