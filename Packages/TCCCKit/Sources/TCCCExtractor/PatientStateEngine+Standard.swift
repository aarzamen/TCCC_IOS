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
    /// loop (`state.py:515–524`):
    ///
    /// 1. `MOIExtractor` — mechanism of injury
    /// 2. `HemorrhageExtractor`
    /// 3. `AirwayExtractor`
    /// 4. `RespirationExtractor`
    /// 5. `CirculationExtractor`
    /// 6. `HeadHypothermiaExtractor`
    /// 7. `FractureExtractor`
    /// 8. `PAWSExtractor`
    /// 9. `VitalsExtractor`
    /// 10. `ClassificationExtractor` — runs last; reads other fields for inference
    public static func standard() -> PatientStateEngine {
        PatientStateEngine(passes: [
            MOIExtractor(),
            HemorrhageExtractor(),
            AirwayExtractor(),
            RespirationExtractor(),
            CirculationExtractor(),
            HeadHypothermiaExtractor(),
            FractureExtractor(),
            PAWSExtractor(),
            VitalsExtractor(),
            ClassificationExtractor(),
        ])
    }
}
