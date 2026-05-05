// ZMISTValidator
//
// Cross-references SLM-generated ZMIST text against the deterministic
// `PatientStateEngine` snapshot. Replaces hallucinated S (Signs), I (Injuries),
// T (Treatment), Evacuation, and Classification lines with state-verified
// values. Discards extra SLM blocks beyond the known patient count, and
// generates state-derived blocks for any state patient with no SLM block.
//
// Mirrors `validate_zmist_against_state` and its helpers
// (`_validate_zmist_section`, `_get_verified_signs`, `_get_verified_injuries`,
// `_get_verified_treatments`, `_get_verified_evacuation`) in
// /Users/ama/TCCC_FEB_2026/src/reports.py (lines 584–956) verbatim.
//
// Block-binding strategy (Option A from Python):
//   1. Read PATIENT_n from the Z-line if present.
//   2. Otherwise bind by insertion order — block N → patients[N].
//   3. Drop blocks that resolve to no known patient.
//   4. Synthesise blocks from state for any state patient without a binding.
//
// Foundation only.

import Foundation
import TCCCDomain

/// Stateless validator for SLM-generated ZMIST reports.
public enum ZMISTValidator: Sendable {

    /// Validate an SLM-generated ZMIST report. See file header for the binding
    /// strategy; mirrors `validate_zmist_against_state` (`reports.py:584–710`).
    ///
    /// - Parameters:
    ///   - zmistContent: Raw ZMIST report from the SLM.
    ///   - patients: Ordered list of patients from the engine snapshot
    ///     (insertion order matches Python's `state_engine.patients` keys).
    /// - Returns: Validated ZMIST text. Empty patient list returns the standard
    ///   "No patients identified in assessment." sentinel.
    public static func validate(
        _ zmistContent: String,
        against patients: [PatientState]
    ) -> String {
        if patients.isEmpty {
            return "No patients identified in assessment."
        }

        // Build a lookup table once. `patients` order is the binding order
        // for blocks that have a redacted Z-line.
        let patientsByID: [String: PatientState] = Dictionary(
            uniqueKeysWithValues: patients.map { ($0.patientId, $0) }
        )
        let validIDs: [String] = patients.map { $0.patientId }

        // 1) Strip SLM wrapper.
        let stripped = SLMWrapperStripper.strip(zmistContent)

        // 2) Split into blocks, one per "ZMIST CASUALTY REPORT" line.
        let blocks = splitIntoBlocks(stripped)

        // 3) Bind each block to a patient ID (Z-line first, insertion-order fallback).
        var binds: [(block: [String], pid: String?)] = []
        for (idx, block) in blocks.enumerated() {
            var pid: String? = readPatientIDFromZLine(block)
            if pid == nil, idx < validIDs.count {
                pid = validIDs[idx]
            }
            binds.append((block, pid))
        }

        // 4) Validate each bound block; discard unknown / duplicate bindings.
        var validatedLines: [String] = []
        var usedPIDs: Set<String> = []

        for (block, pid) in binds {
            guard let pid = pid, let patient = patientsByID[pid] else {
                continue  // unknown PID — discard (matches Python warn-and-skip)
            }
            if usedPIDs.contains(pid) {
                continue  // duplicate binding — discard
            }
            usedPIDs.insert(pid)

            let validated = validateZMISTSection(block, patient: patient)
            validatedLines.append(contentsOf: validated)
            validatedLines.append("")  // blank line between patients
        }

        // 5) For any state patient with no SLM block, generate from state.
        let missing = validIDs.filter { !usedPIDs.contains($0) }
        if !missing.isEmpty {
            let missingPatients = missing.compactMap { patientsByID[$0] }
            let fallbackText = stateGeneratedZMIST(for: missingPatients)
            validatedLines.append(fallbackText)
        }

        let result = validatedLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 6) Last-resort: if nothing survived, regenerate everything from state.
        if result.isEmpty || !result.uppercased().contains("ZMIST") {
            return stateGeneratedZMIST(for: patients)
        }

        return result
    }

    // ------------------------------------------------------------------
    // Block splitting / Z-line parsing
    // ------------------------------------------------------------------

    /// Split a stripped ZMIST string into one block per "ZMIST CASUALTY REPORT"
    /// header line. Mirrors Python's loop in `reports.py:619–634`.
    private static func splitIntoBlocks(_ text: String) -> [[String]] {
        var rawBlocks: [[String]] = []
        var current: [String] = []

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        for line in lines {
            if line.uppercased().contains("ZMIST CASUALTY REPORT") {
                if !current.isEmpty {
                    rawBlocks.append(current)
                }
                current = [line]
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty {
            rawBlocks.append(current)
        }

        // Filter out blocks that don't actually contain a header line.
        return rawBlocks.filter { block in
            block.contains { $0.uppercased().contains("ZMIST CASUALTY REPORT") }
        }
    }

    /// Look for a Z-line in `block` and parse "PATIENT_n" from it. Returns
    /// `nil` if none found (i.e. Z-line missing or redacted).
    /// Mirrors Python's loop in `reports.py:646–652`.
    private static func readPatientIDFromZLine(_ block: [String]) -> String? {
        for line in block {
            let cleaned = line.trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")

            if cleaned.hasPrefix("z ") || cleaned.hasPrefix("z:") {
                // Found Z-line; try to extract a "PATIENT_n" / "PATIENT-n" / "PATIENTn".
                if let match = line.range(
                    of: "(?:PATIENT[_-]?)(\\d+)",
                    options: [.regularExpression, .caseInsensitive]
                ) {
                    let captured = line[match]
                    // Pull the trailing digits.
                    if let digitMatch = captured.range(of: "\\d+", options: .regularExpression) {
                        let digits = String(captured[digitMatch])
                        return "PATIENT_\(digits)"
                    }
                }
                return nil  // Z-line found but no PATIENT_n in it
            }
        }
        return nil
    }

    // ------------------------------------------------------------------
    // Per-block field validation
    // ------------------------------------------------------------------

    /// Mirrors `_validate_zmist_section` (`reports.py:729–819`).
    private static func validateZMISTSection(
        _ block: [String],
        patient: PatientState
    ) -> [String] {
        var validated: [String] = []
        var skipUntilNextField = false

        for line in block {
            // Strip markdown formatting for the comparison key.
            let cleaned = line
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: "*", with: "")
                .replacingOccurrences(of: ":", with: "")
                .trimmingCharacters(in: .whitespaces)

            let detected = detectField(cleaned)

            if let field = detected {
                // We're at a field header — stop skipping previous field's
                // continuation lines.
                skipUntilNextField = false

                switch field {
                case .signs:
                    validated.append("S (Signs):       \(getVerifiedSigns(patient))")
                    skipUntilNextField = true
                    continue
                case .injuries:
                    validated.append("I (Injuries):    \(getVerifiedInjuries(patient))")
                    skipUntilNextField = true
                    continue
                case .treatment:
                    validated.append("T (Treatment):   \(getVerifiedTreatments(patient))")
                    skipUntilNextField = true
                    continue
                case .evacuation:
                    validated.append("Evacuation:      \(getVerifiedEvacuation(patient))")
                    continue
                case .classification:
                    let cls = patient.classification?.rawValue ?? "PENDING"
                    validated.append("Classification:  \(cls)")
                    continue
                case .zap, .mechanism:
                    // Z and M lines pass through (we don't override mechanism).
                    validated.append(line)
                    continue
                }
            }

            // Continuation-line handling for fields we fully replaced.
            if skipUntilNextField {
                if line.uppercased().contains("ZMIST")
                    || line.trimmingCharacters(in: .whitespaces).hasPrefix("=") {
                    validated.append(line)
                }
                continue
            }

            validated.append(line)
        }

        return validated
    }

    /// ZMIST field-line types. Mirrors the dispatch ladder in
    /// `reports.py:_validate_zmist_section`.
    private enum ZMISTField {
        case zap
        case mechanism
        case injuries
        case signs
        case treatment
        case evacuation
        case classification
    }

    /// Detect which ZMIST field (if any) `cleaned` is a header for.
    /// `cleaned` is the line stripped of `:`, `*`, and surrounding whitespace,
    /// lowercased.
    private static func detectField(_ cleaned: String) -> ZMISTField? {
        if cleaned.hasPrefix("s (signs") || cleaned.hasPrefix("s(signs") || cleaned == "s" {
            return .signs
        }
        if cleaned.hasPrefix("i (injuries") || cleaned.hasPrefix("i(injuries") || cleaned == "i" {
            return .injuries
        }
        if cleaned.hasPrefix("t (treatment") || cleaned.hasPrefix("t(treatment") || cleaned == "t" {
            return .treatment
        }
        if cleaned.hasPrefix("evacuation") {
            return .evacuation
        }
        if cleaned.hasPrefix("classification") {
            return .classification
        }
        if cleaned.hasPrefix("z (zap") || cleaned.hasPrefix("z(zap") || cleaned == "z" {
            return .zap
        }
        if cleaned.hasPrefix("m (mechanism") || cleaned.hasPrefix("m(mechanism") || cleaned == "m" {
            return .mechanism
        }
        return nil
    }

    // ------------------------------------------------------------------
    // _get_verified_* helpers (reports.py:822–955)
    // ------------------------------------------------------------------

    /// Mirrors `_get_verified_signs` (`reports.py:853–885`). The Swift Vitals
    /// struct is typed; we render the same "RR x, HR y, BP z, SpO2 w, GCS v"
    /// list, plus consciousness / pulse / skin if present.
    static func getVerifiedSigns(_ patient: PatientState) -> String {
        var signs: [String] = []
        let v = patient.vitals

        var vitalsParts: [String] = []
        if let rr = v.rr { vitalsParts.append("RR \(rr)") }
        if let hr = v.hr { vitalsParts.append("HR \(hr)") }
        if let bp = v.bp {
            let suffix = bp.palpated ? "P" : ""
            vitalsParts.append("BP \(bp.systolic)/\(bp.diastolic)\(suffix)")
        }
        if let spo2 = v.spo2 { vitalsParts.append("SpO2 \(spo2)") }
        if let gcs = v.gcs { vitalsParts.append("GCS \(gcs)") }

        if !vitalsParts.isEmpty {
            signs.append("Vitals: " + vitalsParts.joined(separator: ", "))
        }

        if let loc = patient.march.consciousness {
            signs.append("LOC: \(loc)")
        }
        if let pulse = patient.march.pulseStatus {
            signs.append("Pulse: \(pulse)")
        }
        if let skin = patient.march.skinSigns {
            signs.append("Skin: \(skin)")
        }

        return signs.isEmpty ? "NOT ASSESSED" : signs.joined(separator: "; ")
    }

    /// Mirrors `_get_verified_injuries` (`reports.py:888–905`). Pure MARCH
    /// injuries — hemorrhage location and pneumothorax. NOT mechanism of
    /// injury (that belongs on the M line).
    static func getVerifiedInjuries(_ patient: PatientState) -> String {
        var injuries: [String] = []
        if let loc = patient.march.hemorrhageLocation, !loc.isEmpty {
            injuries.append("Hemorrhage: \(loc)")
        }
        if let resp = patient.march.respirationStatus,
           resp.lowercased().contains("pneumothorax") {
            injuries.append("Possible pneumothorax")
        }
        return injuries.isEmpty ? "See MARCH assessment" : injuries.joined(separator: ", ")
    }

    /// Mirrors `_get_verified_treatments` (`reports.py:908–955`). Includes
    /// MARCH interventions then PAWS-keyword interventions from the typed
    /// `Intervention` list. PAWS-typed assessments (`patient.paws`) are also
    /// included since the iOS port promotes them to first-class fields.
    static func getVerifiedTreatments(_ patient: PatientState) -> String {
        var treatments: [String] = []
        let march = patient.march

        if let h = march.hemorrhageIntervention, !h.isEmpty {
            let suffix = (march.hemorrhageEffective == true) ? " (effective)" : ""
            treatments.append("\(h)\(suffix)")
        }
        if let a = march.airwayIntervention, !a.isEmpty {
            treatments.append(a)
        }
        if let r = march.respirationIntervention, !r.isEmpty {
            treatments.append(r)
        }
        if let c = march.circulationIntervention, !c.isEmpty {
            treatments.append(c)
        }
        if let hyp = march.hypothermiaPrevention, !hyp.isEmpty {
            treatments.append(hyp)
        }

        // Typed PAWS — ensure each is included if not already captured.
        let paws = patient.paws
        for descriptor in [paws.splinting, paws.pain, paws.antibiotics, paws.wounds] {
            guard let desc = descriptor, !desc.isEmpty else { continue }
            if !treatments.contains(desc) {
                treatments.append(desc)
            }
        }

        // PAWS keywords on the flat `interventions` list (mirror Python).
        let pawsKeywords = [
            "splint", "traction", "sager", "sam",
            "pill pack", "pain", "tylenol", "meloxicam", "ketamine",
            "antibiotic", "moxifloxacin",
            "wound care", "irrigat",
        ]
        for intervention in patient.interventions {
            let desc = intervention.description
            let lower = desc.lowercased()
            // Skip tourniquets — already represented by hemorrhageIntervention.
            if lower.contains("tourniquet") { continue }
            if pawsKeywords.contains(where: { lower.contains($0) }),
               !treatments.contains(desc) {
                treatments.append(desc)
            }
        }

        return treatments.isEmpty ? "See MARCH assessment" : treatments.joined(separator: ", ")
    }

    /// Mirrors `_get_verified_evacuation` (`reports.py:822–850`). Reuses the
    /// same litter predicate as MEDEVAC's litter/ambulatory split.
    static func getVerifiedEvacuation(_ patient: PatientState) -> String {
        return StateHelpers.needsLitter(patient) ? "Litter" : "Ambulatory"
    }

    // ------------------------------------------------------------------
    // State-derived ZMIST (used for missing patients & last-resort fallback)
    // ------------------------------------------------------------------

    /// Mirrors `generate_zmist_from_state` (`reports.py:958–1018`) for the
    /// validator's missing-patient + last-resort paths. Layout matches the
    /// Python source so test fixtures that look for "Evacuation:      Litter"
    /// continue to match. The user-facing fallback path lives in
    /// `ZMISTGenerator` (which uses the iOS-specific layout); we keep this one
    /// internal and Python-shaped so validator output stays consistent.
    static func stateGeneratedZMIST(for patients: [PatientState]) -> String {
        var reports: [String] = []
        for patient in patients {
            let march = patient.march

            var injuries: [String] = []
            if let loc = march.hemorrhageLocation, !loc.isEmpty {
                injuries.append("Hemorrhage: \(loc)")
            }
            if injuries.isEmpty {
                injuries.append("See MARCH assessment")
            }

            var signs: [String] = []
            let vitalsStr = formatPythonVitalsLine(patient.vitals)
            if !vitalsStr.isEmpty {
                signs.append(vitalsStr)
            }
            if let loc = march.consciousness {
                signs.append("LOC: \(loc)")
            }
            if signs.isEmpty {
                signs.append("See MARCH assessment")
            }

            var treatments: [String] = []
            if let h = march.hemorrhageIntervention, !h.isEmpty {
                let suffix = (march.hemorrhageEffective == true) ? "(effective)" : ""
                let combined = "\(h) \(suffix)".trimmingCharacters(in: .whitespaces)
                treatments.append(combined)
            }
            if let a = march.airwayIntervention, !a.isEmpty { treatments.append(a) }
            if let r = march.respirationIntervention, !r.isEmpty { treatments.append(r) }
            if let c = march.circulationIntervention, !c.isEmpty { treatments.append(c) }
            if let hyp = march.hypothermiaPrevention, !hyp.isEmpty { treatments.append(hyp) }
            if treatments.isEmpty {
                treatments.append("See MARCH assessment")
            }

            let evacuation = getVerifiedEvacuation(patient)
            let classification = patient.classification?.rawValue ?? "PENDING"
            let mechanism = patient.mechanismOfInjury ?? "UNKNOWN"

            let block = """
                ZMIST CASUALTY REPORT
                =====================
                Z (Zap #):       \(patient.patientId) [REDACTED]
                M (Mechanism):   \(mechanism)
                I (Injuries):    \(injuries.joined(separator: "; "))
                S (Signs):       \(signs.joined(separator: "; "))
                T (Treatment):   \(treatments.joined(separator: "; "))

                Classification:  \(classification)
                Evacuation:      \(evacuation)
                """
            reports.append(block)
        }
        return reports.joined(separator: "\n---\n\n")
    }

    /// Render `Vitals` in the Python "k: v" comma-separated format used by
    /// `generate_zmist_from_state` so the layout stays drop-in compatible.
    private static func formatPythonVitalsLine(_ vitals: Vitals) -> String {
        var parts: [String] = []
        if let hr = vitals.hr { parts.append("HR: \(hr)") }
        if let bp = vitals.bp {
            let suffix = bp.palpated ? "P" : ""
            parts.append("BP: \(bp.systolic)/\(bp.diastolic)\(suffix)")
        }
        if let spo2 = vitals.spo2 { parts.append("SpO2: \(spo2)%") }
        if let rr = vitals.rr { parts.append("RR: \(rr)") }
        if let gcs = vitals.gcs { parts.append("GCS: \(gcs)") }
        return parts.joined(separator: ", ")
    }
}
