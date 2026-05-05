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
    /// Procedural-sedation ketamine routes per 2026 §13 — IV/IO push or
    /// IM. Distinct from the §11 analgesia ketamine because the doses
    /// differ (procedural is 1-2 mg/kg IV/IO or 300mg IM; analgesic is
    /// 25mg IV/IO or 100mg IM).
    private let ketamineProceduralRegex: NSRegularExpression
    private let acetaminophenRegex: NSRegularExpression
    /// Dose capture for acetaminophen — pulls "1000 mg" / "1300 mg" /
    /// "two 650 mg" out of the sentence so the descriptor includes the
    /// actual dose for the §F MEDS row on DD 1380.
    private let acetaminophenDoseRegex: NSRegularExpression
    private let meloxicamRegex: NSRegularExpression
    private let antibioticsRegex: NSRegularExpression
    private let cefadroxilRegex: NSRegularExpression
    private let cephalexinRegex: NSRegularExpression
    private let ceftriaxoneRegex: NSRegularExpression
    private let moxiRegex: NSRegularExpression
    private let woundCareRegex: NSRegularExpression
    private let plasmaRegex: NSRegularExpression

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
        // 2026 §13 procedural-sedation ketamine. The pattern intentionally
        // co-occurs with ketamine — when both fire, the descriptor flags
        // procedural intent. Triggers: explicit "procedural", per-kg dosing,
        // 300 mg IM (analgesia is 100 mg IM), "1-2 mg/kg" or "2-3 mg/kg".
        let ketamineProceduralPattern =
            "procedural\\s+sedation|" +
            "ketamine\\s+(?:1|2)\\s*-\\s*(?:2|3)\\s*mg\\s*/\\s*kg|" +
            "ketamine\\s+\\d+\\s*-\\s*\\d+\\s*mg/kg|" +
            "ketamine\\s+300\\s*mg\\s*im"
        let acetaminophenPattern = "acetaminophen|tylenol"
        // Dose capture — bidirectional. Real medic narration has dose
        // ordering both ways: "Gave 1000 mg of Tylenol" AND "Tylenol
        // 1000 mg PO". Both are matched. Special case "two 650 mg" for
        // the 2026 spec verbatim phrasing.
        let acetaminophenDosePattern =
            "(?:acetaminophen|tylenol)[^.;]{0,60}?(\\d{3,4})\\s*mg|" +
            "(\\d{3,4})\\s*mg[^.;]{0,60}?(?:acetaminophen|tylenol)|" +
            "two\\s+650\\s*mg"
        let meloxicamPattern = "meloxicam"

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

        // 2026 §8 plasma for isolated TBI: "1-2 units of plasma" given when
        // there is no hemorrhage. Recognized as a circulation-adjacent
        // intervention; we record it via PAWSExtractor's "wounds" pathway
        // since it's a fluid administration during care, then surface in
        // the meds log + back-of-card §E Blood Product row downstream.
        let plasmaPattern =
            "(?:1\\s*-\\s*2|one\\s+to\\s+two|1\\s+or\\s+2)\\s+units?\\s+of\\s+plasma|" +
            "(?:gave|giving|administered?|administering)\\s+(?:1|2|one|two)\\s+units?\\s+of\\s+plasma"

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
        self.ketamineProceduralRegex = try! NSRegularExpression(
            pattern: ketamineProceduralPattern, options: [.caseInsensitive])
        self.acetaminophenRegex = try! NSRegularExpression(
            pattern: acetaminophenPattern, options: [.caseInsensitive])
        self.acetaminophenDoseRegex = try! NSRegularExpression(
            pattern: acetaminophenDosePattern, options: [.caseInsensitive])
        self.meloxicamRegex = try! NSRegularExpression(
            pattern: meloxicamPattern, options: [.caseInsensitive])
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
        self.plasmaRegex = try! NSRegularExpression(
            pattern: plasmaPattern, options: [.caseInsensitive])
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
            } else if hasMatch(sentence, regex: ketamineProceduralRegex) {
                // Procedural sedation (per-kg or 300mg IM) gets a distinct
                // descriptor — the validator can later cross-check against
                // §13 wound-care context.
                medType = "Ketamine procedural sedation administered"
            } else if hasMatch(sentence, regex: ketamineRegex) {
                medType = "Ketamine administered"
            } else if hasMatch(sentence, regex: acetaminophenRegex) {
                let dose = extractAcetaminophenDose(sentence)
                medType = dose.map { "Acetaminophen \($0) administered" }
                    ?? "Acetaminophen administered"
            } else if hasMatch(sentence, regex: meloxicamRegex) {
                medType = "Meloxicam administered"
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

        // ---- 2026 §8 plasma for isolated TBI ----------------------------
        // Recorded as a generic .medication intervention. The descriptor
        // notes the TBI context so reports can route it to the §E Blood
        // Product row on DD 1380 back-of-card.
        if hasMatch(sentence, regex: plasmaRegex) {
            let existing = updated.interventions.map { $0.description.lowercased() }
                .joined(separator: "|")
            if !existing.contains("plasma") {
                updated.interventions.append(
                    Intervention(
                        timestamp: context.timestamp,
                        kind: .medication,
                        description: "Plasma administered (isolated TBI, 1-2 units)"
                    )
                )
            }
        }

        return updated
    }

    // MARK: - Acetaminophen dose helper

    private func extractAcetaminophenDose(_ text: String) -> String? {
        let nsText = text as NSString
        let r = NSRange(location: 0, length: nsText.length)
        guard let m = acetaminophenDoseRegex.firstMatch(
            in: text, options: [], range: r)
        else { return nil }
        // Three alternations, each with its own capture-group slot:
        //   group 1: drug-then-dose form
        //   group 2: dose-then-drug form
        //   group 3 (none): "two 650 mg" literal — no group, infer from match.
        for groupIdx in 1...min(2, m.numberOfRanges - 1) {
            let g = m.range(at: groupIdx)
            if g.location != NSNotFound, g.length > 0 {
                let val = nsText.substring(with: g)
                return "\(val) mg"
            }
        }
        // "two 650 mg" literal fallback.
        let matched = nsText.substring(with: m.range).lowercased()
        if matched.contains("two") && matched.contains("650") {
            return "1300 mg (two 650 mg)"
        }
        return nil
    }

    // MARK: - Helpers

    private func hasMatch(_ text: String, regex: NSRegularExpression) -> Bool {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: fullRange) != nil
    }
}
