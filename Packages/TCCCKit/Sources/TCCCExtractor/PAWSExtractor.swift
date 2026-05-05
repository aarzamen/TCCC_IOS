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
    //
    // 2026 vocabulary additions per
    // reference/rubric/extracted/march_paws_vocabulary_2026.json:
    //   - Suzetrigine added to CWMP regimen (§11)
    //   - Esketamine IN added (§11)
    //   - Acetaminophen 2026 dose 1000–1300mg q8h (§11) — recognition unchanged,
    //     dose extraction handled by VitalsExtractor downstream
    //   - PO antibiotics changed from moxifloxacin to cefadroxil (§12)
    //   - IV/IO/IM antibiotics changed from ertapenem to ceftriaxone (§12)
    //   - Cephalexin recognized as the 2026 PO alternative

    private let painMedsRegex: NSRegularExpression
    private let combatPillPackRegex: NSRegularExpression
    private let suzetrigineRegex: NSRegularExpression
    private let esketamineRegex: NSRegularExpression
    private let ketamineRegex: NSRegularExpression
    private let antibioticsRegex: NSRegularExpression
    private let cefadroxilRegex: NSRegularExpression
    private let cephalexinRegex: NSRegularExpression
    private let ceftriaxoneRegex: NSRegularExpression
    private let moxiRegex: NSRegularExpression
    private let woundCareRegex: NSRegularExpression

    public init() {
        // Pain medications — 2026 CWMP + ketamine family + Esketamine IN.
        let painMedsPattern =
            "combat\\s*pill\\s*pack|tylenol|meloxicam|acetaminophen|" +
            "motrin|ibuprofen|ketamine|esketamine|suzetrigine|pain\\s*meds?"

        let combatPillPackPattern = "combat\\s*pill\\s*pack"
        let suzetriginePattern = "suzetrigine"
        // Esketamine MUST be matched before ketamine — otherwise the bare
        // "ketamine" token swallows the descriptor. The regex below uses a
        // word boundary so "esketamine" is only matched as the discrete drug
        // name, not as part of "ketamine".
        let esketaminePattern = "\\besketamine\\b"
        // Ketamine: word boundary on the LEFT prevents matching "esketamine".
        let ketaminePattern = "(?<!es)ketamine"

        // Antibiotics — 2026 PO regimen (cefadroxil, cephalexin) and
        // IV/IO/IM regimen (ceftriaxone), plus retained moxi/ertapenem
        // recognition for backward compatibility.
        let antibioticsPattern =
            "moxifloxacin|moxi|antibiotics?|ertapenem|cefadroxil|" +
            "cephalexin|ceftriaxone"
        let cefadroxilPattern = "cefadroxil"
        let cephalexinPattern = "cephalexin"
        let ceftriaxonePattern = "ceftriaxone"
        let moxiPattern = "moxifloxacin|moxi"

        // Wound care (irrigation, packing, dressing care).
        let woundCarePattern =
            "irrigate|irrigation|pack(?:ed|ing)?\\s*(?:the\\s*)?wound|wound\\s*care"

        self.painMedsRegex = try! NSRegularExpression(
            pattern: painMedsPattern, options: [.caseInsensitive])
        self.combatPillPackRegex = try! NSRegularExpression(
            pattern: combatPillPackPattern, options: [.caseInsensitive])
        self.suzetrigineRegex = try! NSRegularExpression(
            pattern: suzetriginePattern, options: [.caseInsensitive])
        self.esketamineRegex = try! NSRegularExpression(
            pattern: esketaminePattern, options: [.caseInsensitive])
        self.ketamineRegex = try! NSRegularExpression(
            pattern: ketaminePattern, options: [.caseInsensitive])
        self.antibioticsRegex = try! NSRegularExpression(
            pattern: antibioticsPattern, options: [.caseInsensitive])
        self.cefadroxilRegex = try! NSRegularExpression(
            pattern: cefadroxilPattern, options: [.caseInsensitive])
        self.cephalexinRegex = try! NSRegularExpression(
            pattern: cephalexinPattern, options: [.caseInsensitive])
        self.ceftriaxoneRegex = try! NSRegularExpression(
            pattern: ceftriaxonePattern, options: [.caseInsensitive])
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

        // ---- Pain management (state.py:901–912 + 2026 §11 additions) ---
        // Sub-classifier order matters: more specific drugs first, then the
        // catch-all. Esketamine BEFORE ketamine so "esketamine" doesn't fall
        // through to the generic ketamine descriptor.
        if hasMatch(sentence, regex: painMedsRegex) && updated.paws.pain == nil {
            let medType: String
            if hasMatch(sentence, regex: combatPillPackRegex) {
                medType = "Combat pill pack administered"
            } else if hasMatch(sentence, regex: suzetrigineRegex) {
                medType = "Suzetrigine administered"
            } else if hasMatch(sentence, regex: esketamineRegex) {
                medType = "Esketamine administered"
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

        // ---- Antibiotics (2026 §12 — cefadroxil/cephalexin PO,
        //                   ceftriaxone IV/IO/IM; legacy moxi/ertapenem
        //                   retained for backward compatibility) ----------
        if hasMatch(sentence, regex: antibioticsRegex) &&
            updated.paws.antibiotics == nil {
            let abxType: String
            if hasMatch(sentence, regex: cefadroxilRegex) {
                abxType = "Cefadroxil administered"
            } else if hasMatch(sentence, regex: ceftriaxoneRegex) {
                abxType = "Ceftriaxone administered"
            } else if hasMatch(sentence, regex: cephalexinRegex) {
                abxType = "Cephalexin administered"
            } else if hasMatch(sentence, regex: moxiRegex) {
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
