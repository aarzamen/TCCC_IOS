// ZMISTGenerator
//
// Produces the state-derived ZMIST fallback. Mirrors
// `generate_zmist_from_state` in /Users/ama/TCCC_FEB_2026/src/reports.py
// (lines 958–1018) for *logic*. The output text layout follows the iOS port
// contract specified in CLAUDE.md / Phase 5 task: one Z/M/I/S/T block per
// patient with single-letter prefixes and bullet separators.
//
// Field ordering and missing-value placeholders mirror Python:
//   - I (injuries):    joined with "; ", default "see narrative"
//                      (Python uses "See MARCH assessment"; we follow the
//                      Phase 5 spec which calls for "see narrative".)
//   - T (treatments):  joined with "; ", default "see narrative"
//   - S (signs):       compact single-line vitals; missing fields use "—".
//
// The mechanism-of-injury default ("UNKNOWN") preserves Python's literal.
//
// Foundation only.

import Foundation
import TCCCDomain

/// State-derived ZMIST report generator.
public struct ZMISTGenerator: Sendable {

    public init() {}

    public static let fallbackBanner = MedevacGenerator.fallbackBanner

    /// Default placeholder when no narrative content is available for a field.
    public static let narrativePlaceholder = "see narrative"

    /// Placeholder for individual missing vitals fields (Python uses "—" too
    /// when the typed-vitals layer can't produce a value).
    public static let missingVitalsPlaceholder = "—"

    /// Mechanism-of-injury fallback. Mirrors Python literal.
    public static let unknownMechanism = "UNKNOWN"

    /// Build a ZMIST report. Empty patient list emits a banner-only message,
    /// same as MEDEVAC.
    public func generate(
        from patients: [PatientState],
        at timestamp: Date = Date()
    ) -> Report {
        let body = format(patients: patients)
        return Report(
            kind: .zmist,
            formattedText: body,
            generatedAt: timestamp,
            isFallback: true
        )
    }

    // MARK: Formatting

    private func format(patients: [PatientState]) -> String {
        if patients.isEmpty {
            return """
            \(ZMISTGenerator.fallbackBanner)

            No patients identified in assessment.
            """
        }

        var blocks: [String] = []
        for patient in patients {
            blocks.append(formatBlock(patient))
        }

        // Header banner, blank line, then each patient block separated by a
        // blank line. The trailing block has no trailing newline.
        return ZMISTGenerator.fallbackBanner + "\n\n" + blocks.joined(separator: "\n\n")
    }

    private func formatBlock(_ patient: PatientState) -> String {
        let zLine = formatZ(patient)
        let mLine = formatM(patient)
        let iLine = formatI(patient)
        let sLine = formatS(patient)
        let tLine = formatT(patient)

        return """
        \(patient.patientId)
        Z: \(zLine)
        M: \(mLine)
        I: \(iLine)
        S: \(sLine)
        T: \(tLine)
        """
    }

    // ------------------------------------------------------------------
    // Field formatters
    // ------------------------------------------------------------------

    /// Z: <patientId> · <classification or PENDING>
    private func formatZ(_ patient: PatientState) -> String {
        let classification = patient.classification?.rawValue ?? "PENDING"
        return "\(patient.patientId) · \(classification)"
    }

    /// M: mechanism of injury, "UNKNOWN" when missing.
    private func formatM(_ patient: PatientState) -> String {
        guard let moi = patient.mechanismOfInjury, !moi.isEmpty else {
            return ZMISTGenerator.unknownMechanism
        }
        return moi
    }

    /// I: injuries joined with "; ". Defaults to placeholder.
    ///
    /// Mirrors Python `_get_verified_injuries` selection but extends it with
    /// `patient.injuries` (which the iOS engine populates as a top-level field
    /// — see `PatientState.injuries`). Hemorrhage location and pneumothorax
    /// are still picked up from MARCH.
    private func formatI(_ patient: PatientState) -> String {
        var injuries: [String] = []

        if let loc = patient.march.hemorrhageLocation, !loc.isEmpty {
            injuries.append("Hemorrhage: \(loc)")
        }

        if let resp = patient.march.respirationStatus,
           resp.lowercased().contains("pneumothorax") {
            injuries.append("Possible pneumothorax")
        }

        for injury in patient.injuries where !injury.isEmpty {
            // Avoid trivial duplicates against hemorrhage location text.
            if !injuries.contains(injury) {
                injuries.append(injury)
            }
        }

        if injuries.isEmpty {
            return ZMISTGenerator.narrativePlaceholder
        }
        return injuries.joined(separator: "; ")
    }

    /// S: HR <hr> · BP <sys>/<dia><P?> · SpO2 <spo2>% · RR <rr> · GCS <gcs>
    /// Missing fields use the placeholder ("—") so the block layout is stable.
    private func formatS(_ patient: PatientState) -> String {
        let v = patient.vitals
        let missing = ZMISTGenerator.missingVitalsPlaceholder

        let hr = v.hr.map(String.init) ?? missing
        let bp: String
        if let bpStruct = v.bp {
            let suffix = bpStruct.palpated ? "P" : ""
            bp = "\(bpStruct.systolic)/\(bpStruct.diastolic)\(suffix)"
        } else {
            bp = missing
        }
        let spo2 = v.spo2.map { "\($0)%" } ?? missing
        let rr = v.rr.map(String.init) ?? missing
        let gcs = v.gcs.map(String.init) ?? missing

        return "HR \(hr) · BP \(bp) · SpO2 \(spo2) · RR \(rr) · GCS \(gcs)"
    }

    /// T: treatments joined with "; ". Mirrors Python `_get_verified_treatments`
    /// selection ordering (hemorrhage, airway, respiration, circulation,
    /// hypothermia, then PAWS interventions from the `interventions` list).
    private func formatT(_ patient: PatientState) -> String {
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

        // PAWS — Python pulls from the flat `patient.interventions` strings,
        // filtering by keyword. The Swift port has typed PAWSAssessment
        // fields plus typed Intervention objects — prefer the typed fields
        // when they exist.
        let paws = patient.paws
        if let s = paws.splinting, !s.isEmpty, !treatments.contains(s) {
            treatments.append(s)
        }
        if let p = paws.pain, !p.isEmpty, !treatments.contains(p) {
            treatments.append(p)
        }
        if let ab = paws.antibiotics, !ab.isEmpty, !treatments.contains(ab) {
            treatments.append(ab)
        }
        if let w = paws.wounds, !w.isEmpty, !treatments.contains(w) {
            treatments.append(w)
        }

        // Pull any other typed Interventions (skip ones already covered by
        // MARCH-specific fields or PAWS to avoid double-listing).
        for intervention in patient.interventions {
            let desc = intervention.description
            if desc.isEmpty || treatments.contains(desc) {
                continue
            }
            // Skip tourniquets — already represented by hemorrhageIntervention.
            if intervention.kind == .tourniquet {
                continue
            }
            treatments.append(desc)
        }

        if treatments.isEmpty {
            return ZMISTGenerator.narrativePlaceholder
        }
        return treatments.joined(separator: "; ")
    }
}
