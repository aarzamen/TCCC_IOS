// PatientStateEngine
//
// Faithful Swift port of `PatientStateEngine` from
// /Users/ama/TCCC_FEB_2026/src/state.py (lines 320–528).
//
// Per-sentence dispatch order from `update_from_transcript` (state.py:481–528):
//
//   1. Normalize spoken numbers across the whole chunk.
//   2. Sentence-tokenise the chunk (lookbehind regex on .!?\s+ or \n+).
//   3. For each sentence:
//        a. Patient-switch detection FIRST  -> may mutate currentPatientID
//        b. Get/create the current patient + update timestamps
//        c. Run every extractor pass in order, threading state through
//   4. After all chunks: `_update_march_phase` was called in Python; we
//      omit the auto-phase update because the Swift engine treats marchPhase
//      as a UI hint and mutation happens via dedicated setters in later phases.
//
// Engine semantics preserved verbatim:
//   - `currentPatientID` defaults to "PATIENT_1".
//   - First-mention timestamp set ONLY if currently nil.
//   - Last-update timestamp ALWAYS overwritten.
//   - Patient state is created on first mention.
//
// Concurrency: implemented as an actor so the engine can be safely shared
// across the UI's @MainActor and the speech-recognition stream actor without
// introducing data races. All public mutation goes through `processTranscript`.
//
// Foundation only.

import Foundation
import TCCCDomain

public actor PatientStateEngine {

    // MARK: - State

    /// Active patient store, keyed by patient id ("PATIENT_1", "PATIENT_2", ...).
    public private(set) var patients: [String: PatientState] = [:]

    /// Patient currently in focus. Patient-switch detection mutates this.
    public private(set) var currentPatientID: String = "PATIENT_1"

    // MARK: - Dependencies

    private let passes: [any ExtractorPass]
    private let normalizer: SpokenNumberNormalizer
    private let tokenizer: SentenceTokenizer
    private let negation: NegationDetector
    private let switcher: PatientSwitcher

    // MARK: - Init

    public init(
        passes: [any ExtractorPass],
        normalizer: SpokenNumberNormalizer = SpokenNumberNormalizer(),
        tokenizer: SentenceTokenizer = SentenceTokenizer(),
        negation: NegationDetector = NegationDetector(),
        switcher: PatientSwitcher = PatientSwitcher()
    ) {
        self.passes = passes
        self.normalizer = normalizer
        self.tokenizer = tokenizer
        self.negation = negation
        self.switcher = switcher
        // Mirror Python __init__: ensure PATIENT_1 exists from the start.
        self.patients["PATIENT_1"] = PatientState(patientId: "PATIENT_1")
    }

    // MARK: - Public API

    /// Process a transcript chunk and update the patient state(s).
    ///
    /// Mirrors `state.py:PatientStateEngine.update_from_transcript`:
    ///   1. Normalize spoken vital-sign numbers in the chunk.
    ///   2. Sentence-tokenise.
    ///   3. For each sentence, detect a patient switch first, then ensure the
    ///      patient row exists, refresh timestamps, build the
    ///      `ExtractionContext`, and pass it through every extractor.
    public func processTranscript(_ text: String, timestamp: Date = Date()) {
        let normalized = normalizer.normalize(text)
        let sentences = tokenizer.tokenize(normalized)
        let unixTimestamp = timestamp.timeIntervalSince1970

        for sentence in sentences {
            // 1. Patient-switch detection FIRST (P1 #3 in state.py).
            if let newID = switcher.detectSwitch(in: sentence) {
                currentPatientID = newID
                ensurePatientExists(currentPatientID)
            }

            // 2. Get-or-create current patient and refresh timestamps.
            ensurePatientExists(currentPatientID)
            var patient = patients[currentPatientID]!
            if patient.timestampFirstMention == nil {
                patient.timestampFirstMention = unixTimestamp
            }
            patient.timestampLastUpdate = unixTimestamp

            // 3. Build context and dispatch through every pass.
            let isNegated = negation.sentenceHasNegationMarker(sentence)
            let context = ExtractionContext(
                originalText: text,
                normalizedText: normalized,
                sentence: sentence,
                timestamp: timestamp,
                currentPatientID: currentPatientID,
                isNegated: isNegated)

            var current = patient
            for pass in passes {
                current = pass.apply(current, context: context)
            }
            patients[currentPatientID] = current
        }
    }

    /// Snapshot copy of the entire patient dict.
    public func snapshot() -> [String: PatientState] {
        return patients
    }

    /// Snapshot copy of one patient's state, or nil if unknown.
    public func snapshot(of patientId: String) -> PatientState? {
        return patients[patientId]
    }

    // MARK: - Internal helpers

    /// Ensure a row exists for `patientId`. Mirrors `_ensure_patient_exists`.
    private func ensurePatientExists(_ patientId: String) {
        if patients[patientId] == nil {
            patients[patientId] = PatientState(patientId: patientId)
        }
    }
}
