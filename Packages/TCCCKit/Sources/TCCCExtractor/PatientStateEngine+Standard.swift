// PatientStateEngine+Standard
//
// Convenience factory that returns a `PatientStateEngine` wired with the full
// TCCC dispatch chain. Order mirrors `state.py:515–524` (process_transcript)
// so per-sentence side effects are observed in the same sequence as Python.
//
// Foundation only.

import Foundation
import TCCCDomain

extension PatientStateEngine {

    /// Returns an engine wired with the full TCCC extractor dispatch chain.
    ///
    /// Pass order matches the Python `PatientStateEngine.process_transcript`
    /// loop (`state.py:515–524`), with one 2026-sprint deviation: the legacy
    /// `HeadHypothermiaExtractor` was split into `HypothermiaExtractor` (§7)
    /// and `TBIExtractor` (§8) per 2026 TCCC Guidelines structure. Both run
    /// in the same slot the legacy extractor occupied.
    ///
    /// 1. `MOIExtractor` — mechanism of injury
    /// 2. `HemorrhageExtractor`
    /// 3. `AirwayExtractor`
    /// 4. `RespirationExtractor`
    /// 5. `CirculationExtractor`
    /// 6. `HypothermiaExtractor` — 2026 §7
    /// 7. `TBIExtractor` — 2026 §8
    /// 8. `FractureExtractor`
    /// 9. `PAWSExtractor`
    /// 10. `VitalsExtractor`
    /// 11. `ClassificationExtractor` — runs last; reads other fields for inference
    public static func standard() -> PatientStateEngine {
        PatientStateEngine(passes: [
            MOIExtractor(),
            HemorrhageExtractor(),
            AirwayExtractor(),
            RespirationExtractor(),
            CirculationExtractor(),
            HypothermiaExtractor(),
            TBIExtractor(),
            FractureExtractor(),
            PAWSExtractor(),
            VitalsExtractor(),
            ClassificationExtractor(),
        ])
    }
}
