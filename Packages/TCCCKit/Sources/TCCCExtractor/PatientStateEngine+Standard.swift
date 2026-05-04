// PatientStateEngine+Standard
//
// Convenience factory that returns a `PatientStateEngine` wired with the
// extractor passes owned by Lane A of Phase 4 — hemorrhage, airway, and
// head/hypothermia. The full TCCC dispatch chain (respiration, circulation,
// fractures, vitals, PAWS, classification) lives in Lanes B and C and will be
// added to this factory in a follow-up commit once those passes land.
//
// Foundation only.

import Foundation
import TCCCDomain

extension PatientStateEngine {

    /// Returns an engine wired with the standard TCCC extractor passes.
    ///
    /// Currently includes the three Lane A extractors:
    /// `HemorrhageExtractor`, `AirwayExtractor`, `HeadHypothermiaExtractor`.
    /// Lanes B and C (respiration, circulation, fractures, vitals, PAWS,
    /// classification) will be wired here in a follow-up commit, restoring
    /// full parity with the Python `PatientStateEngine` dispatch order.
    public static func standard() -> PatientStateEngine {
        PatientStateEngine(passes: [
            HemorrhageExtractor(),
            AirwayExtractor(),
            HeadHypothermiaExtractor(),
        ])
    }
}
