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

    /// Append-only event log for this encounter. A3 dual-write.
    public private(set) var log = EncounterLog()
    private var asrCount = 0
    private var factCount = 0
    private var lifecycleCount = 1   // init seeds "lc-1"

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
        // Seed a lifecycle event so a fresh encounter's log is never empty.
        // timestampUnix: 0 keeps init deterministic (no Date() in the constructor).
        self.log.append(.lifecycle(.init(
            id: "lc-1", patientId: "PATIENT_1", timestampUnix: 0, kind: .encounterStarted)))
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
        let before = patients                               // A3: capture for the diff
        let normalized = normalizer.normalize(text)
        let sentences = tokenizer.tokenize(normalized)
        let unixTimestamp = timestamp.timeIntervalSince1970

        for sentence in sentences {
            // 1. Patient-switch detection FIRST (P1 #3 in state.py).
            if let newID = switcher.detectSwitch(in: sentence) {
                currentPatientID = newID
                ensurePatientExists(currentPatientID, timestamp: unixTimestamp)
            }

            // 2. Get-or-create current patient and refresh timestamps.
            ensurePatientExists(currentPatientID, timestamp: unixTimestamp)
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

        emitEvents(text: text, before: before, timestamp: unixTimestamp)
        // No re-fold: the imperative loop above already maintains `patients` as the
        // materialized projection. project(log) (used by restore + the equivalence
        // tests) is provably equal to it (A2 inverse property + A3 equivalence), so
        // recomputing it here would be O(N) wasted work per transcript line.
    }

    /// Snapshot copy of the entire patient dict.
    public func snapshot() -> [String: PatientState] {
        return patients
    }

    /// Snapshot copy of one patient's state, or nil if unknown.
    public func snapshot(of patientId: String) -> PatientState? {
        return patients[patientId]
    }

    /// Snapshot copy of the encounter log. A3 dual-write accessor.
    public func snapshotLog() -> EncounterLog { log }

    /// Events appended since `index` — a small slice copy, for incremental persistence
    /// without deep-copying the entire `EncounterLog` struct. `index` is a count cursor;
    /// out-of-range yields `[]`.
    public func newEvents(since index: Int) -> [EncounterEvent] {
        guard index < log.events.count else { return [] }
        return Array(log.events[index...])
    }

    /// Apply typed field writes to one patient. This is the ONLY non-extraction
    /// mutation entry; it accepts only the typed `PatientStateFieldWrite` vocabulary,
    /// so the engine remains the sole writer of `PatientState`.
    public func apply(_ writes: [PatientStateFieldWrite], to patientId: String) {
        guard !writes.isEmpty else { return }
        ensurePatientExists(patientId)
        var p = patients[patientId]!
        for write in writes { Self.applyWrite(write, to: &p) }
        p.timestampLastUpdate = Date().timeIntervalSince1970
        patients[patientId] = p
    }

    // MARK: - Operator event recording (A4 dual-write)

    private var opCount = 0

    /// Record + apply an operator-accepted fact: append the `operatorAcceptedFact`
    /// event, then apply the write IN PLACE to the materialized `patients` (BLOCK A —
    /// identical to `project`'s `operatorAcceptedFact` arm, without re-folding the log).
    /// `ensurePatientExists` guarantees the row first.
    public func recordOperatorAcceptedFact(write: PatientStateFieldWrite, factId: String?,
        domain: String, field: String, rawValue: String?, to patientId: String,
        timestamp: Date = Date()) {
        let unix = timestamp.timeIntervalSince1970
        ensurePatientExists(patientId, timestamp: unix)
        opCount += 1
        log.append(.operatorAcceptedFact(.init(
            id: "op-\(opCount)", patientId: patientId, timestampUnix: unix,
            write: write, sourceFactId: factId, domain: domain, field: field, rawValue: rawValue)))
        // Incremental: apply the accepted write in place (identical to project()'s
        // operatorAcceptedFact arm) instead of re-folding the whole log.
        var p = patients[patientId]!          // ensurePatientExists guaranteed the row
        Self.applyWrite(write, to: &p)
        p.timestampLastUpdate = unix          // == the event's timestampUnix, as project sets it
        patients[patientId] = p
    }

    /// Record an operator rejection (audit only — never mutates state).
    public func recordOperatorRejectedFact(factId: String?, domain: String, field: String,
        rawValue: String?, to patientId: String, timestamp: Date = Date()) {
        opCount += 1
        log.append(.operatorRejectedFact(.init(
            id: "op-\(opCount)", patientId: patientId, timestampUnix: timestamp.timeIntervalSince1970,
            write: nil, sourceFactId: factId, domain: domain, field: field, rawValue: rawValue)))
    }

    // MARK: - Restore + lifecycle (sub-cycle B)

    /// Re-seat the engine from a persisted log (replay-on-launch). Resumes id counters
    /// from per-type event counts (ids are sequential, so count == max) so subsequent
    /// events don't collide with replayed ones.
    public func restore(_ restoredLog: EncounterLog) {
        log = restoredLog
        patients = Self.project(restoredLog)
        var asr = 0, fact = 0, op = 0, life = 0
        var lastAsrPatient: String?
        for event in restoredLog.events {
            switch event {
            case .asrSegment(let p):            asr += 1; lastAsrPatient = p.patientId
            case .deterministicFact:            fact += 1
            case .operatorAcceptedFact,
                 .operatorRejectedFact:         op += 1
            case .lifecycle:                    life += 1
            }
        }
        asrCount = asr; factCount = fact; opCount = op; lifecycleCount = life
        currentPatientID = lastAsrPatient ?? "PATIENT_1"
    }

    /// Append an audit-only lifecycle marker (End Care / archival). `.encounterEnded`
    /// and `.archived` are inert in `project`, so no re-projection is needed.
    public func recordLifecycle(_ kind: LifecyclePayload.Kind, timestamp: Date = Date()) {
        lifecycleCount += 1
        log.append(.lifecycle(.init(
            id: "lc-\(lifecycleCount)", patientId: currentPatientID,
            timestampUnix: timestamp.timeIntervalSince1970, kind: kind)))
    }

    // MARK: - Internal helpers

    /// Emit the asrSegment + per-patient deterministicFact events for one transcript call.
    private func emitEvents(text: String, before: [String: PatientState], timestamp: Double) {
        asrCount += 1
        let segId = "seg-\(asrCount)"
        log.append(.asrSegment(.init(
            id: segId, patientId: currentPatientID, timestampUnix: timestamp,
            text: text, backend: "engine", isFinal: true)))
        for (pid, after) in patients.sorted(by: { $0.key < $1.key }) {
            let beforeP = before[pid] ?? PatientState(patientId: pid)
            for delta in Self.diff(beforeP, after) {
                factCount += 1
                log.append(.deterministicFact(.init(
                    id: "fact-\(factCount)", patientId: pid, timestampUnix: timestamp,
                    delta: delta, evidenceIds: [segId], extractor: "deterministic")))
            }
        }
    }

    /// Ensure a row exists for `patientId`. Mirrors `_ensure_patient_exists`.
    /// On creation, appends a `.lifecycle(.encounterStarted)` event so `project`
    /// can guarantee the key-set even for patients with no clinical facts.
    /// `timestamp` is threaded from the processing call site — do NOT call Date() here.
    private func ensurePatientExists(_ patientId: String, timestamp: Double = 0) {
        if patients[patientId] == nil {
            patients[patientId] = PatientState(patientId: patientId)
            lifecycleCount += 1
            log.append(.lifecycle(.init(
                id: "lc-\(lifecycleCount)", patientId: patientId,
                timestampUnix: timestamp, kind: .encounterStarted)))
        }
    }
}
