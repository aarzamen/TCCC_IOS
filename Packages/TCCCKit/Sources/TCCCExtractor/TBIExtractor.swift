// TBIExtractor
//
// Second half of the 2026 split of HeadHypothermiaExtractor — handles
// TBI-relevant assessment findings: AVPU consciousness, pupil response,
// and the legacy GCS scalar. Corresponds to 2026 TCCC Guidelines §8.
// The hypothermia half lives in HypothermiaExtractor (§7).
//
// Reference: reference/rubric/extracted/march_paws_vocabulary_2026.json,
// MARCH.H_tbi. Phase 3 will expand to the 2026 vocabulary additions
// (herniation signs, hypertonic saline, EtCO2 ventilation targets,
// SBP > 100 threshold). This extractor preserves the existing AVPU /
// pupils / GCS patterns from the Python prototype verbatim for test
// parity.
//
// Note on AVPU vs DD 1380: AVPU is a Section C vital row on the form,
// not a MARCH-H field. We continue to write it into `march.consciousness`
// for compatibility with the existing extractor surface; the §C grid in
// Phase 4 will read from that same field.
//
// Foundation only.

import Foundation
import TCCCDomain

public struct TBIExtractor: ExtractorPass {

    // MARK: - Patterns

    private let avpuAlert: NSRegularExpression
    private let avpuVoice: NSRegularExpression
    private let avpuPain: NSRegularExpression
    private let avpuUnresponsive: NSRegularExpression

    private let pupilsBasic: NSRegularExpression
    private let pupilsCombined: NSRegularExpression

    private let gcs: NSRegularExpression

    // 2026 §8 additions
    private let posturing: NSRegularExpression
    private let asymmetricPupil: NSRegularExpression
    private let hypertonicSaline: NSRegularExpression

    public init() {
        // Verbatim from state.py:428–434 (head_patterns avpu/pupils/gcs).
        self.avpuAlert = try! NSRegularExpression(
            pattern: "\\balert\\b|\\boriented\\b|a\\s*and\\s*o|alert\\s*and\\s*oriented",
            options: [.caseInsensitive])
        self.avpuVoice = try! NSRegularExpression(
            pattern: "responds?\\s*to\\s*voice|voice\\s*responsive",
            options: [.caseInsensitive])
        self.avpuPain = try! NSRegularExpression(
            pattern: "responds?\\s*to\\s*pain|pain\\s*responsive",
            options: [.caseInsensitive])
        self.avpuUnresponsive = try! NSRegularExpression(
            pattern: "unresponsive|unconscious|u\\s*on\\s*avpu",
            options: [.caseInsensitive])

        self.pupilsBasic = try! NSRegularExpression(
            pattern: "pupils?\\s*(are\\s*)?(equal|unequal|dilated|constricted|reactive|fixed)",
            options: [.caseInsensitive])
        self.pupilsCombined = try! NSRegularExpression(
            pattern: "(equal|unequal)\\s*(and\\s*)?(reactive|fixed)",
            options: [.caseInsensitive])

        self.gcs = try! NSRegularExpression(
            pattern: "gcs\\s*(?:is\\s*|of\\s*)?(\\d+)",
            options: [.caseInsensitive])

        // 2026 §8 herniation signs — a single match pushes a finding into
        // injuries[]. "asymmetric pupil" is a herniation sign distinct from
        // the basic equal/unequal pupil descriptor; "posturing" (decorticate
        // or decerebrate) is not currently captured by the legacy patterns.
        self.posturing = try! NSRegularExpression(
            pattern: "\\bposturing\\b|decorticate|decerebrate",
            options: [.caseInsensitive])
        self.asymmetricPupil = try! NSRegularExpression(
            pattern: "asymmetric\\s+pupils?|asymmetric\\s+pupillary",
            options: [.caseInsensitive])

        // 2026 §8 hypertonic saline herniation protocol.
        // Per march_paws_vocabulary_2026.json MARCH.H_tbi.hypertonic saline
        // for herniation: "250ml of 3% or 5% hypertonic saline OR 30ml of
        // 23.4% hypertonic saline IV/IO over at least 10 minutes". Max 2
        // doses, repeat at 20 min if no response.
        self.hypertonicSaline = try! NSRegularExpression(
            pattern:
                "hypertonic\\s+saline|" +
                "250\\s*ml\\s+of\\s+(?:3|5)\\s*%|" +
                "30\\s*ml\\s+of\\s+23\\.?4\\s*%",
            options: [.caseInsensitive])
    }

    // MARK: - Apply

    public func apply(_ state: PatientState, context: ExtractionContext) -> PatientState {
        var s = state
        var march = s.march
        let text = context.sentence

        // AVPU — first match wins (Python iterates in order and breaks).
        let avpuTable: [(NSRegularExpression, String)] = [
            (avpuAlert, "Alert"),
            (avpuVoice, "Voice"),
            (avpuPain, "Pain"),
            (avpuUnresponsive, "Unresponsive"),
        ]
        for (pattern, status) in avpuTable {
            if matches(pattern, text) {
                march.consciousness = status
                break
            }
        }

        // Pupils — try basic, then combined; first match wins.
        if let pupilDesc = extractPupilsBasic(text) {
            march.pupilResponse = pupilDesc
        } else if let pupilDesc = extractPupilsCombined(text) {
            march.pupilResponse = pupilDesc
        }

        // GCS — assign to typed Vitals.gcs (Vitals validates via init range).
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        if let m = gcs.firstMatch(in: text, options: [], range: fullRange),
           m.numberOfRanges > 1 {
            let r = m.range(at: 1)
            if r.location != NSNotFound,
               let value = Int(nsText.substring(with: r)) {
                s.vitals = Vitals(
                    hr: s.vitals.hr,
                    bp: s.vitals.bp,
                    spo2: s.vitals.spo2,
                    rr: s.vitals.rr,
                    gcs: value,
                    temperatureCelsius: s.vitals.temperatureCelsius,
                    capillaryRefillSeconds: s.vitals.capillaryRefillSeconds)
            }
        }

        s.march = march

        // 2026 §8 herniation signs — record into injuries[] so reports can
        // surface them. Dedup on the descriptor.
        if matches(posturing, text) {
            let exists = s.injuries.contains(where: { $0.lowercased().contains("posturing") })
            if !exists { s.injuries.append("Posturing (decorticate/decerebrate)") }
        }
        if matches(asymmetricPupil, text) {
            let exists = s.injuries.contains(where: { $0.lowercased().contains("asymmetric pupil") })
            if !exists { s.injuries.append("Asymmetric pupils (herniation sign)") }
        }

        // 2026 §8 hypertonic saline administration — record as a medication
        // intervention. Distinct from generic .medication descriptor so
        // reports can format herniation-protocol fluids correctly.
        if matches(hypertonicSaline, text) {
            let existing = s.interventions.map { $0.description.lowercased() }
                .joined(separator: "|")
            if !existing.contains("hypertonic saline") {
                s.interventions.append(Intervention(
                    timestamp: context.timestamp,
                    kind: .medication,
                    description: "Hypertonic saline administered (TBI herniation protocol)"))
            }
        }

        return s
    }

    // MARK: - Pupil extraction

    private func extractPupilsBasic(_ text: String) -> String? {
        let nsText = text as NSString
        let r = NSRange(location: 0, length: nsText.length)
        guard let m = pupilsBasic.firstMatch(in: text, options: [], range: r),
              m.numberOfRanges > 2 else { return nil }
        let g2r = m.range(at: 2)
        guard g2r.location != NSNotFound else { return nil }
        let result = nsText.substring(with: g2r)
        return result.isEmpty ? nil : result.lowercased()
    }

    private func extractPupilsCombined(_ text: String) -> String? {
        let nsText = text as NSString
        let r = NSRange(location: 0, length: nsText.length)
        guard let m = pupilsCombined.firstMatch(in: text, options: [], range: r),
              m.numberOfRanges > 3 else { return nil }
        let g1r = m.range(at: 1)
        let g3r = m.range(at: 3)
        guard g1r.location != NSNotFound, g3r.location != NSNotFound else { return nil }
        let g1 = nsText.substring(with: g1r)
        let g3 = nsText.substring(with: g3r)
        return "\(g1) and \(g3)".lowercased()
    }

    // MARK: - Helpers

    private func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let nsText = text as NSString
        let r = NSRange(location: 0, length: nsText.length)
        return regex.firstMatch(in: text, options: [], range: r) != nil
    }
}
