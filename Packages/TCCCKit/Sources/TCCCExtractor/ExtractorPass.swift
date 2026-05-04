import Foundation
import TCCCDomain

/// Context passed to every extractor on every sentence iteration.
///
/// Mirrors the per-sentence loop in `state.py:process_transcript` (around
/// lines 500–525). Extractors get both the original chunk text and the
/// post-normalization text so they can choose which to regex against —
/// vital extraction wants normalized numbers; mechanism-of-injury extraction
/// often wants the original phrasing.
public struct ExtractionContext: Sendable {
    /// Raw transcript chunk as the engine received it.
    public let originalText: String
    /// Spoken-number-normalized form of `originalText`.
    public let normalizedText: String
    /// One sentence carved out of `normalizedText`. Extractors operate on this.
    public let sentence: String
    /// Time the chunk arrived at the engine.
    public let timestamp: Date
    /// Patient currently in focus (after patient-switch detection).
    public let currentPatientID: String
    /// True if the sentence was tagged as containing a clinical negation
    /// (e.g. "no signs of pneumothorax"). Extractors should usually skip
    /// positive findings when this is true.
    public let isNegated: Bool

    public init(
        originalText: String,
        normalizedText: String,
        sentence: String,
        timestamp: Date,
        currentPatientID: String,
        isNegated: Bool
    ) {
        self.originalText = originalText
        self.normalizedText = normalizedText
        self.sentence = sentence
        self.timestamp = timestamp
        self.currentPatientID = currentPatientID
        self.isNegated = isNegated
    }
}

/// One extraction step in the engine's per-sentence pipeline.
///
/// Each conforming type reads the sentence, decides if it matches its
/// concern (hemorrhage, vitals, classification, etc.), and returns a new
/// `PatientState` with the relevant fields updated. If nothing matches,
/// the implementation returns the input state unchanged.
///
/// Implementations must be pure (no side effects, no IO, no logging),
/// `Sendable`, and stateless across calls. The engine instantiates each
/// pass once and reuses it across many sentences and patients.
public protocol ExtractorPass: Sendable {
    func apply(_ state: PatientState, context: ExtractionContext) -> PatientState
}
