// PAWSExtractor
//
// Faithful Swift port of `_extract_paws` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 898–929), plus the three
// PAWS regex patterns at lines 471–479:
//
//     paws_patterns = {
//         "pain_meds":  re.compile(r"combat\s*pill\s*pack|tylenol|meloxicam|"
//                                  r"acetaminophen|motrin|ibuprofen|ketamine|"
//                                  r"pain\s*meds?", re.I),
//         "antibiotics": re.compile(r"moxifloxacin|moxi|antibiotics?|ertapenem", re.I),
//         "wound_care": re.compile(r"irrigate|irrigation|pack(?:ed|ing)?\s*"
//                                  r"(?:the\s*)?wound|wound\s*care", re.I),
//     }
//
// Two principled extensions over the Python source (per PatientState.swift
// design note 2):
//
//   1. `state.paws` is a top-level typed struct (`PAWSAssessment`), not a
//      string flattened into `interventions`. The Python prototype appends
//      a descriptor string into `patient.interventions` (e.g.
//      "Combat pill pack administered"). The Swift mirror writes the same
//      descriptor into both `state.paws.<field>` AND `state.interventions`
//      so report-generation code can read either source.
//
//   2. `context.isNegated` — when the engine flags a sentence as negated
//      (e.g. "no antibiotics needed", "denies pain medication"), this
//      extractor refuses to record any PAWS finding. Python's `_extract_paws`
//      lacks this guard.
//
// The Python "already-recorded" guard (the `not in str(patient.interventions)`
// check) is mirrored here using the typed `state.paws.<field>` slot — once a
// pain/antibiotic/wound descriptor is set, repeated mentions in later
// sentences do not overwrite it. Splinting is currently handled by
// `_extract_fractures` in Python (Lane B's `FractureExtractor`), so this
// extractor leaves `state.paws.splinting` untouched.
//
// Foundation only — no SwiftUI, UIKit, Combine, or external deps.

import Foundation
import TCCCDomain

public struct PAWSExtractor: ExtractorPass {

    // MARK: - Compiled regex patterns

    private let painMedsRegex: NSRegularExpression
    private let combatPillPackRegex: NSRegularExpression
    private let ketamineRegex: NSRegularExpression
    private let antibioticsRegex: NSRegularExpression
    private let moxiRegex: NSRegularExpression
    private let woundCareRegex: NSRegularExpression

    public init() {
        // Pain medications. Group-less; we just need a hit.
        let painMedsPattern =
            "combat\\s*pill\\s*pack|tylenol|meloxicam|acetaminophen|" +
            "motrin|ibuprofen|ketamine|pain\\s*meds?"

        // Sub-classifiers (case-insensitive).
        let combatPillPackPattern = "combat\\s*pill\\s*pack"
        let ketaminePattern = "ketamine"

        // Antibiotics.
        let antibioticsPattern = "moxifloxacin|moxi|antibiotics?|ertapenem"
        let moxiPattern = "moxifloxacin|moxi"

        // Wound care (irrigation, packing, dressing care).
        let woundCarePattern =
            "irrigate|irrigation|pack(?:ed|ing)?\\s*(?:the\\s*)?wound|wound\\s*care"

        self.painMedsRegex = try! NSRegularExpression(
            pattern: painMedsPattern, options: [.caseInsensitive])
        self.combatPillPackRegex = try! NSRegularExpression(
            pattern: combatPillPackPattern, options: [.caseInsensitive])
        self.ketamineRegex = try! NSRegularExpression(
            pattern: ketaminePattern, options: [.caseInsensitive])
        self.antibioticsRegex = try! NSRegularExpression(
            pattern: antibioticsPattern, options: [.caseInsensitive])
        self.moxiRegex = try! NSRegularExpression(
            pattern: moxiPattern, options: [.caseInsensitive])
        self.woundCareRegex = try! NSRegularExpression(
            pattern: woundCarePattern, options: [.caseInsensitive])
    }

    // MARK: - ExtractorPass

    public func apply(
        _ state: PatientState, context: ExtractionContext
    ) -> PatientState {
        if context.isNegated {
            return state
        }

        let sentence = context.sentence
        var updated = state

        // ---- Pain management (state.py:901–912) -------------------------
        if hasMatch(sentence, regex: painMedsRegex) && updated.paws.pain == nil {
            let medType: String
            if hasMatch(sentence, regex: combatPillPackRegex) {
                medType = "Combat pill pack administered"
            } else if hasMatch(sentence, regex: ketamineRegex) {
                medType = "Ketamine administered"
            } else {
                medType = "Pain medication administered"
            }
            updated.paws.pain = medType
            updated.interventions.append(
                Intervention(
                    timestamp: context.timestamp,
                    kind: .painManagement,
                    description: medType
                )
            )
        }

        // ---- Antibiotics (state.py:914–923) -----------------------------
        if hasMatch(sentence, regex: antibioticsRegex) &&
            updated.paws.antibiotics == nil {
            let abxType: String
            if hasMatch(sentence, regex: moxiRegex) {
                abxType = "Moxifloxacin administered"
            } else {
                abxType = "Antibiotics administered"
            }
            updated.paws.antibiotics = abxType
            updated.interventions.append(
                Intervention(
                    timestamp: context.timestamp,
                    kind: .antibiotic,
                    description: abxType
                )
            )
        }

        // ---- Wound care (state.py:925–929) ------------------------------
        if hasMatch(sentence, regex: woundCareRegex) && updated.paws.wounds == nil {
            let descriptor = "Wound care performed"
            updated.paws.wounds = descriptor
            updated.interventions.append(
                Intervention(
                    timestamp: context.timestamp,
                    kind: .woundCare,
                    description: descriptor
                )
            )
        }

        return updated
    }

    // MARK: - Helpers

    private func hasMatch(_ text: String, regex: NSRegularExpression) -> Bool {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: fullRange) != nil
    }
}
