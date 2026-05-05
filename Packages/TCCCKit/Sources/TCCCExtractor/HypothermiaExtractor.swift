// HypothermiaExtractor
//
// One half of the 2026 split of HeadHypothermiaExtractor — handles
// hypothermia prevention only. Corresponds to 2026 TCCC Guidelines §7.
// The other half (AVPU + pupils + GCS) lives in TBIExtractor (§8).
//
// Reference: reference/rubric/extracted/march_paws_vocabulary_2026.json,
// MARCH.H_hypothermia. The 2026 vocabulary expansion (insulation, active
// heating blanket, exterior impermeable enclosure bag, etc.) is added in
// Phase 3; this extractor preserves the existing pattern verbatim from
// the Python prototype to maintain test parity.
//
// Foundation only.

import Foundation
import TCCCDomain

public struct HypothermiaExtractor: ExtractorPass {

    private let hypothermia: NSRegularExpression

    public init() {
        // Verbatim from state.py:436 (`hypothermia` regex inside head_patterns).
        self.hypothermia = try! NSRegularExpression(
            pattern: "hypothermia\\s*wrap|prevent\\s*hypothermia|wrapping|blanket|insulate",
            options: [.caseInsensitive])
    }

    public func apply(_ state: PatientState, context: ExtractionContext) -> PatientState {
        var s = state
        let text = context.sentence
        let nsText = text as NSString
        let r = NSRange(location: 0, length: nsText.length)

        if hypothermia.firstMatch(in: text, options: [], range: r) != nil {
            s.march.hypothermiaPrevention = "Hypothermia wrap applied"
            let existing = s.interventions.map { $0.description.lowercased() }
                .joined(separator: "|")
            if !existing.contains("hypothermia") {
                s.interventions.append(Intervention(
                    timestamp: context.timestamp,
                    kind: .hypothermiaPrevention,
                    description: "Hypothermia prevention measures"))
            }
        }

        return s
    }
}
