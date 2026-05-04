// StateHelpers
//
// Internal helpers ported verbatim from the Python fallback path in
// /Users/ama/TCCC_FEB_2026/src/reports.py:
//
//   - `_calculate_patient_counts`       (reports.py:95–128)
//   - `_infer_classification`           (reports.py:131–175)
//   - `_calculate_litter_ambulatory`    (reports.py:178–232)
//   - `_determine_special_equipment`    (reports.py:235–268)
//   - `_get_verified_evacuation`        (reports.py:822–850)  — same litter
//                                                                logic, used by
//                                                                ZMIST too.
//
// Logic is preserved field-for-field. Where the Python source reads
// `vitals["HR"]` we use the typed `Vitals.hr`. Where it reads
// `march.hemorrhage_intervention` we use `MARCHState.hemorrhageIntervention`.
//
// Foundation only.

import Foundation
import TCCCDomain

/// Tally of patients by triage classification.
struct PatientCounts {
    var urgent: Int = 0
    var urgentSurgical: Int = 0
    var priority: Int = 0
    var routine: Int = 0
    var convenience: Int = 0
    var pending: Int = 0

    var total: Int {
        urgent + urgentSurgical + priority + routine + convenience + pending
    }
}

/// Litter / ambulatory split.
struct LitterAmbulatory {
    var litter: Int = 0
    var ambulatory: Int = 0

    var total: Int { litter + ambulatory }
}

enum StateHelpers {

    // ------------------------------------------------------------------
    // _calculate_patient_counts (reports.py:95–128)
    // ------------------------------------------------------------------

    static func calculatePatientCounts(_ patients: [PatientState]) -> PatientCounts {
        var counts = PatientCounts()

        for patient in patients {
            // Mirror the Python coercion: `(patient.classification or "").lower()`.
            // If classification is missing or "pending", infer from clinical
            // findings.
            let raw = patient.classification?.rawValue.lowercased() ?? ""
            let classification: String
            if raw.isEmpty || raw == "pending" {
                classification = inferClassification(patient)
            } else {
                classification = raw
            }

            // Order matters: "urgent surgical" must be checked before "urgent"
            // because "urgent" is a substring of "urgent surgical".
            if classification.contains("urgent surgical") {
                counts.urgentSurgical += 1
            } else if classification.contains("urgent") {
                counts.urgent += 1
            } else if classification.contains("priority") {
                counts.priority += 1
            } else if classification.contains("routine") {
                counts.routine += 1
            } else if classification.contains("convenience") {
                counts.convenience += 1
            } else {
                // Default unclassified to urgent (conservative).
                counts.urgent += 1
            }
        }

        return counts
    }

    // ------------------------------------------------------------------
    // _infer_classification (reports.py:131–175)
    // ------------------------------------------------------------------

    static func inferClassification(_ patient: PatientState) -> String {
        let march = patient.march
        let vitals = patient.vitals

        // Urgent Surgical indicators
        let urgentSurgicalIndicators: [Bool] = [
            (march.respirationIntervention ?? "") == "Chest seal applied",
            (march.respirationStatus?.lowercased() ?? "").contains("pneumothorax"),
            (march.consciousness?.lowercased() ?? "") == "unresponsive",
        ]
        if urgentSurgicalIndicators.contains(true) {
            return "urgent surgical"
        }

        // Urgent indicators
        let hrOverHundred = (vitals.hr ?? 0) > 100
        let bpHypotensive: Bool = {
            guard let bp = vitals.bp else { return false }
            return bp.systolic < 100
        }()
        let urgentIndicators: [Bool] = [
            (march.hemorrhageIntervention?.lowercased() ?? "").contains("tourniquet"),
            hrOverHundred,
            bpHypotensive,
            march.airwayIntervention != nil,
        ]
        if urgentIndicators.contains(true) {
            return "urgent"
        }

        // Priority indicators
        let priorityIndicators: [Bool] = [
            march.hemorrhageIdentified && march.hemorrhageIntervention == nil,
            ["voice", "pain"].contains(march.consciousness?.lowercased() ?? ""),
        ]
        if priorityIndicators.contains(true) {
            return "priority"
        }

        // Alert + no major interventions => routine
        if (march.consciousness?.lowercased() ?? "") == "alert" {
            if march.hemorrhageIntervention == nil && march.airwayIntervention == nil {
                return "routine"
            }
        }

        // Default to urgent (conservative triage)
        return "urgent"
    }

    // ------------------------------------------------------------------
    // _calculate_litter_ambulatory (reports.py:178–232)
    // ------------------------------------------------------------------

    static func calculateLitterAmbulatory(_ patients: [PatientState]) -> LitterAmbulatory {
        var result = LitterAmbulatory()

        for patient in patients {
            let isExplicitlyAmbulatory = isExplicitlyAmbulatoryClass(patient)
            let needsLitter = needsLitter(patient)
            let isAmbulatory = isAmbulatory(patient, alreadyNeedsLitter: needsLitter)

            // Explicit classification overrides default
            if isExplicitlyAmbulatory && !needsLitter {
                result.ambulatory += 1
            } else if needsLitter {
                result.litter += 1
            } else if isAmbulatory {
                result.ambulatory += 1
            } else {
                // Default to litter (safer assumption)
                result.litter += 1
            }
        }

        return result
    }

    /// Mirrors Python: classification contains "priority", "routine",
    /// "walking", or "ambulatory".
    private static func isExplicitlyAmbulatoryClass(_ patient: PatientState) -> Bool {
        let classification = patient.classification?.rawValue.lowercased() ?? ""
        return ["priority", "routine", "walking", "ambulatory"].contains { term in
            classification.contains(term)
        }
    }

    /// Mirrors `_calculate_litter_ambulatory` and `_get_verified_evacuation`
    /// litter criteria. Both Python helpers use the same predicate; we extract
    /// it once so MEDEVAC and ZMIST agree by construction.
    static func needsLitter(_ patient: PatientState) -> Bool {
        let march = patient.march
        let classification = patient.classification?.rawValue.lowercased() ?? ""

        let consciousness = march.consciousness?.lowercased() ?? ""
        let consciousnessLitter = ["unresponsive", "pain", "voice"].contains(consciousness)

        let hemorrhageLocation = march.hemorrhageLocation?.lowercased() ?? ""
        let bilateralLowerExt = hemorrhageLocation.contains("bilateral")

        let legOrThighLocation = ["leg", "thigh"].contains { hemorrhageLocation.contains($0) }
        let legThighWithTQ = (march.hemorrhageIntervention != nil) &&
            (march.hemorrhageLocation != nil) &&
            legOrThighLocation

        let lowerExtremityHemorrhage = ["leg", "thigh", "femur"].contains { loc in
            hemorrhageLocation.contains(loc)
        } && march.hemorrhageLocation != nil

        let majorRespIntervention = march.respirationIntervention != nil
        let majorAirwayIntervention = march.airwayIntervention != nil
        let urgentClass = classification.contains("urgent")

        return consciousnessLitter
            || bilateralLowerExt
            || legThighWithTQ
            || lowerExtremityHemorrhage
            || majorRespIntervention
            || majorAirwayIntervention
            || urgentClass
    }

    private static func isAmbulatory(_ patient: PatientState, alreadyNeedsLitter: Bool) -> Bool {
        let consciousness = patient.march.consciousness?.lowercased() ?? ""
        return consciousness == "alert" && !alreadyNeedsLitter
    }

    // ------------------------------------------------------------------
    // _determine_special_equipment (reports.py:235–268)
    // ------------------------------------------------------------------

    /// `transcript` is optional context; the engine may not have a transcript
    /// available at report-generation time, so the helper falls back to
    /// patient-state inspection (same as Python).
    static func determineSpecialEquipment(
        transcript: String,
        patients: [PatientState]
    ) -> String {
        let lower = transcript.lowercased()

        // Mirror Python's `\bhoist\b` etc. word-boundary regexes.
        if matchesWord(lower, word: "hoist") { return "B-Hoist" }
        if matchesWord(lower, word: "extraction") { return "C-Extraction" }
        if matchesWord(lower, word: "ventilator") { return "D-Ventilator" }

        // Python: `\bvent\b(?!\w)` — standalone "vent" only.
        if matchesStandaloneVent(lower) { return "D-Ventilator" }

        // Clinical fallback: cricothyroidotomy implies ventilator likely needed.
        for patient in patients {
            if let airway = patient.march.airwayIntervention?.lowercased(),
               airway.contains("cric") {
                return "D-Ventilator"
            }
        }

        return "A-None"
    }

    private static func matchesWord(_ haystack: String, word: String) -> Bool {
        // Mirrors Python's `\b<word>\b` match.
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        return haystack.range(of: pattern, options: .regularExpression) != nil
    }

    private static func matchesStandaloneVent(_ haystack: String) -> Bool {
        // `\bvent\b(?!\w)` — same as `\bvent\b` for ASCII alnum, but be
        // explicit: vent followed by a non-word char or end-of-string.
        return haystack.range(of: "\\bvent\\b(?!\\w)", options: .regularExpression) != nil
    }
}
