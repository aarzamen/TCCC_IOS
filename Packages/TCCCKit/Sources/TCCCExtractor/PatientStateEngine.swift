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

    /// Snapshot of engine state taken before the outstanding provisional chunk was
    /// processed. Non-nil ⇒ a provisional chunk is the log tail and may be revised.
    /// `tail` records the log length AFTER the provisional chunk was processed; it is
    /// used by `reviseProvisional` to detect whether a foreign event interleaved.
    private var provisionalBoundary: (cursor: Int,
                                      tail: Int,
                                      patients: [String: PatientState],
                                      currentPatientID: String)?

    public var hasProvisional: Bool { provisionalBoundary != nil }

    private var asrCount = 0
    private var factCount = 0
    private var lifecycleCount = 1   // init seeds "lc-1"

    private var sensorAssociation: SensorAssociationPayload?
    /// A still-valid operator consent whose transport dropped. It holds no
    /// authority to ingest; only a reconnect of the same device/encounter/patient
    /// can turn it back into an active binding. Memory only — never reconstructed
    /// from the log, so a restored audit record confers nothing.
    private var suspendedSensorAssociation: SensorAssociationPayload?
    private var sensorProtectedFields: Set<SensorVitalField> = []
    private var sensorReadingIDs: Set<UUID> = []
    private var lastSensorReceipt: Date?
    private var lastSensorObservationTime: Date?

    /// The single binding that currently carries operator consent, whether it is
    /// live or waiting out a transport drop. At most one of the two is non-nil.
    private var sensorAuthority: SensorAssociationPayload? {
        sensorAssociation ?? suspendedSensorAssociation
    }

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
    public func processTranscript(_ text: String, timestamp: Date = Date(), backend: String = "engine") {
        let before = patients                               // A3: capture for the diff
        let normalized = normalizer.normalize(text)
        let sentences = tokenizer.tokenize(normalized)
        let unixTimestamp = timestamp.timeIntervalSince1970

        for sentence in sentences {
            // 1. Patient-switch detection FIRST (P1 #3 in state.py).
            if let newID = switcher.detectSwitch(in: sentence) {
                if newID != currentPatientID { revokeSensorAssociation(timestamp: timestamp) }
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

        emitEvents(text: text, before: before, timestamp: unixTimestamp, backend: backend)
        // No re-fold: the imperative loop above already maintains `patients` as the
        // materialized projection. project(log) (used by restore + the equivalence
        // tests) is provably equal to it (A2 inverse property + A3 equivalence), so
        // recomputing it here would be O(N) wasted work per transcript line.
    }

    /// Commit a chunk as provisional: record a rollback boundary, then extract.
    /// The chunk's events become the log tail until `reviseProvisional`/`settleProvisional`.
    public func commitProvisional(_ text: String, timestamp: Date = Date()) {
        // Capture pre-extraction state (the rollback point).
        let cursor = log.events.count
        let priorPatients = patients
        let priorPatientID = currentPatientID
        let priorAuthorityID = sensorAuthority?.id
        processTranscript(text, timestamp: timestamp)
        // A spoken patient switch revokes sensor ownership immediately. Keep
        // that audit decision before the revisable speech tail even if a later
        // ASR refinement changes the patient-switch words.
        let rollbackCursor = revocationFence(from: cursor, priorAuthorityID: priorAuthorityID)
        // Record `tail` AFTER extraction so reviseProvisional can detect whether
        // a foreign event was appended between commit and revise.
        provisionalBoundary = (cursor: rollbackCursor,
                               tail: log.events.count,
                               patients: priorPatients,
                               currentPatientID: priorPatientID)
    }

    /// Replace the outstanding provisional chunk with refined text. Rolls engine state
    /// back to the boundary, retains the chunk's asrSegment(s) as `isFinal:false` audit
    /// events, truncates, and re-extracts on the refined text. The boundary is refreshed
    /// so a subsequent revision (rare) is also valid.
    ///
    /// If no provisional boundary is outstanding, this is a no-op by design (loss-safe):
    /// the prior committed line stands untouched and `refinedText` is silently dropped.
    /// This is preferable to a hard failure on a field medical device.
    public func reviseProvisional(_ refinedText: String, timestamp: Date = Date()) {
        guard let b = provisionalBoundary else {
            // No-op on misuse by design (loss-safe): the prior committed line stands.
            // assertionFailure is debug-only and would crash release builds on the device.
            return
        }
        precondition(b.cursor <= log.events.count, "boundary cursor beyond log tail")

        // IMPORTANT (tail-guard): verify the provisional chunk is still the exact log
        // tail. If a foreign event (e.g. recordLifecycle / recordOperatorAcceptedFact)
        // was appended after commitProvisional but before this call, truncating at
        // b.cursor would silently discard that foreign event — PHI/audit loss.
        guard log.events.count == b.tail else {
            // Loss-safe fallback: a foreign event interleaved. Do NOT truncate.
            // Settle the original provisional as-is and append the refined text as a
            // fresh chunk. Both the original provisional text and the foreign event
            // survive in the log; the refined text lands on top. This is the rare path.
            provisionalBoundary = nil
            processTranscript(refinedText, timestamp: timestamp)
            return
        }

        // Normal path: provisional chunk is still the tail — roll back and re-extract.

        // Capture retired asrSegment(s) in [cursor...) for audit before truncation.
        let retired: [ASRSegmentPayload] = log.events[b.cursor...].compactMap {
            if case .asrSegment(let p) = $0 { return p }
            return nil
        }
        patients = b.patients
        currentPatientID = b.currentPatientID
        log.truncate(toCount: b.cursor)
        // Note: asrCount/factCount/lifecycleCount are intentionally NOT rolled back.
        // The refined chunk gets higher event ids than the truncated one, keeping ids
        // monotonically increasing. This is safe: ids are inert to project().
        for seg in retired {
            log.append(.asrSegment(.init(id: seg.id + "-retired", patientId: seg.patientId,
                timestampUnix: seg.timestampUnix, text: seg.text, backend: seg.backend,
                isFinal: false)))
        }
        // Refresh the boundary to the post-audit position so the re-extracted chunk is
        // again the revisable tail.
        let newCursor = log.events.count
        let priorPatients = b.patients
        let priorPatientID = b.currentPatientID
        let priorAuthorityID = sensorAuthority?.id
        processTranscript(refinedText, timestamp: timestamp)
        // Same rule as commitProvisional: if THIS refinement is what gave up
        // connection ownership, a further refinement must not truncate that
        // revocation away while the engine stays unbound.
        provisionalBoundary = (cursor: revocationFence(from: newCursor, priorAuthorityID: priorAuthorityID),
                               tail: log.events.count,
                               patients: priorPatients,
                               currentPatientID: priorPatientID)
    }

    /// Index just past the revocation a just-extracted chunk caused, so that
    /// decision sits before the revisable tail; `cursor` when consent (active or
    /// suspended) is unchanged. Revocations are inert in `project`, so keeping
    /// them while rolling patient state back to `cursor` stays equivalent.
    private func revocationFence(from cursor: Int, priorAuthorityID: String?) -> Int {
        guard priorAuthorityID != sensorAuthority?.id,
              let revocationIndex = log.events[cursor...].lastIndex(where: {
                  if case .sensorAssociation(let association) = $0 { return association.kind == .revoked }
                  return false
              }) else { return cursor }
        return revocationIndex + 1
    }

    /// Settle the outstanding provisional: it is now permanent. No state change.
    public func settleProvisional() {
        provisionalBoundary = nil
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

    /// Only permanent events are safe for append-only storage. A sensor-driven
    /// drain may run while the next speech chunk is provisional; excluding that
    /// tail prevents persistence of events a later refinement can replace.
    public func persistableEvents(since index: Int) -> [EncounterEvent] {
        let end = provisionalBoundary?.cursor ?? log.events.count
        guard index >= 0, index < end else { return [] }
        return Array(log.events[index..<end])
    }

    /// Apply typed field writes to one patient. This is the ONLY non-extraction
    /// mutation entry; it accepts only the typed `PatientStateFieldWrite` vocabulary,
    /// so the engine remains the sole writer of `PatientState`.
    ///
    /// - Warning: TEST-ONLY. Unlike `recordOperatorAcceptedFact`, this does **not**
    ///   append an event to `log`, so after calling it `snapshot() != project(log)` for
    ///   the written field, and a crash/restore (which re-folds the persisted log) would
    ///   lose the write. It is currently reachable only from `PatientStateApplyTests`.
    ///   Do not use it on the persisted runtime path — route operator writes through
    ///   `recordOperatorAcceptedFact`, which logs. If a non-test caller ever needs this,
    ///   make it emit a `.deterministicFact` / `.operatorAcceptedFact` event first.
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
    private var lastOperatorDecisionUptime: TimeInterval = 0

    public func operatorRevision() -> Int { opCount }

    /// A completed capture segment is extracted once. If an operator decision
    /// landed while it was being recognized, retain the words for review instead
    /// of allowing the delayed result to supersede that decision.
    public func processCaptureTranscript(_ text: String, operatorRevision: Int,
        requestStartedAt: TimeInterval? = nil, timestamp: Date = Date(),
        backend: String = "appleSpeech") -> Bool {
        let decisionAfterRequest = requestStartedAt.map { lastOperatorDecisionUptime >= $0 } ?? false
        guard opCount == operatorRevision, !decisionAfterRequest else {
            recordCaptureEvidence("REVIEW REQUIRED · " + text, timestamp: timestamp, backend: backend)
            return false
        }
        processTranscript(text, timestamp: timestamp, backend: backend)
        return true
    }

    /// Incomplete capture is durable evidence, never a clinical-state mutation.
    public func recordCaptureEvidence(_ text: String, timestamp: Date = Date(),
        backend: String = "appleSpeech") {
        log.append(.asrSegment(.init(id: "capture-" + UUID().uuidString,
            patientId: currentPatientID, timestampUnix: timestamp.timeIntervalSince1970,
            text: text, backend: backend, isFinal: false)))
    }

    /// Record + apply an operator-accepted fact: append the `operatorAcceptedFact`
    /// event, then apply the write IN PLACE to the materialized `patients` (BLOCK A —
    /// identical to `project`'s `operatorAcceptedFact` arm, without re-folding the log).
    /// `ensurePatientExists` guarantees the row first.
    public func recordOperatorAcceptedFact(write: PatientStateFieldWrite, factId: String?,
        domain: String, field: String, rawValue: String?, to patientId: String,
        timestamp: Date = Date()) {
        lastOperatorDecisionUptime = ProcessInfo.processInfo.systemUptime
        // A dropped connection does not end the operator's authority over the
        // fields they corrected, so a suspended binding protects them too.
        if sensorAuthority?.patientId == patientId, let field = SensorVitalField.matching(write) {
            sensorProtectedFields.insert(field)
        }
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
        lastOperatorDecisionUptime = ProcessInfo.processInfo.systemUptime
        if sensorAuthority?.patientId == patientId {
            if let protected = SensorVitalField.matching(alias: field) {
                sensorProtectedFields.insert(protected)
            } else if let factId,
                      let event = log.events.last(where: { $0.id == factId }),
                      case .sensorObservation(let observation) = event,
                      observation.patientId == patientId {
                if observation.reading.pulseRate != nil { sensorProtectedFields.insert(.pulseRate) }
                if observation.reading.spo2 != nil { sensorProtectedFields.insert(.spo2) }
            }
        }
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
        provisionalBoundary = nil
        // Audit records of association, suspension or resumption are history, not
        // permission: a replayed log never grants ingest or resume authority.
        sensorAssociation = nil
        suspendedSensorAssociation = nil
        sensorProtectedFields.removeAll()
        sensorReadingIDs.removeAll()
        lastSensorReceipt = nil
        lastSensorObservationTime = nil
        var asr = 0, fact = 0, op = 0, life = 0
        var lastAsrPatient: String?
        for event in restoredLog.events {
            switch event {
            case .asrSegment(let p):            asr += 1; lastAsrPatient = p.patientId
            case .deterministicFact:            fact += 1
            case .operatorAcceptedFact,
                 .operatorRejectedFact:         op += 1
            case .lifecycle:                    life += 1
            case .sensorAssociation:            break
            case .sensorObservation(let p):     sensorReadingIDs.insert(p.reading.id)
            }
        }
        asrCount = asr; factCount = fact; opCount = op; lifecycleCount = life
        currentPatientID = lastAsrPatient ?? "PATIENT_1"
    }

    /// Append an audit-only lifecycle marker (End Care / archival). `.encounterEnded`
    /// and `.archived` are inert in `project`, so no re-projection is needed.
    public func recordLifecycle(_ kind: LifecyclePayload.Kind, timestamp: Date = Date()) {
        if kind == .encounterEnded || kind == .archived { revokeSensorAssociation(timestamp: timestamp) }
        lifecycleCount += 1
        log.append(.lifecycle(.init(
            id: "lc-\(lifecycleCount)", patientId: currentPatientID,
            timestampUnix: timestamp.timeIntervalSince1970, kind: kind)))
    }

    // MARK: - Local pulse-oximeter evidence

    /// Explicit operator association. The default matches the single-casualty
    /// UI; speech may select another engine patient, so check focus atomically.
    /// Rebinding is the operator action that releases prior vital protections,
    /// and it supersedes any consent still suspended by a transport drop.
    public func associateSensor(deviceID: String, deviceName: String,
        connectionID: UUID, encounterID: UUID, patientId: String = "PATIENT_1",
        timestamp: Date = Date()) -> SensorAssociationPayload? {
        guard patientId == currentPatientID, patients[patientId] != nil,
              !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              timestamp.timeIntervalSince1970.isFinite else { return nil }
        revokeSensorAssociation(timestamp: timestamp)
        settleProvisional()
        let id = "sensor-association-" + UUID().uuidString
        let association = SensorAssociationPayload(id: id, associationID: id,
            patientId: patientId, timestampUnix: timestamp.timeIntervalSince1970,
            deviceID: deviceID, deviceName: deviceName, connectionID: connectionID,
            encounterID: encounterID, eventFence: log.events.count, kind: .associated)
        log.append(.sensorAssociation(association))
        sensorAssociation = association
        sensorProtectedFields.removeAll()
        lastSensorReceipt = nil
        lastSensorObservationTime = nil
        return association
    }

    /// Match a disconnect to its association so an old connection cannot revoke
    /// a later operator binding. Passing nil is the lifecycle/off revoke-all path,
    /// which must also end a consent that is merely waiting out a transport drop.
    public func revokeSensorAssociation(associationID: String? = nil, timestamp: Date = Date()) {
        guard let association = sensorAuthority,
              associationID == nil || associationID == association.id else { return }
        settleProvisional()
        log.append(.sensorAssociation(.init(
            id: "sensor-revocation-" + UUID().uuidString, associationID: association.associationID,
            patientId: association.patientId, timestampUnix: timestamp.timeIntervalSince1970,
            deviceID: association.deviceID, deviceName: association.deviceName,
            connectionID: association.connectionID, encounterID: association.encounterID,
            eventFence: association.eventFence, kind: .revoked)))
        sensorAssociation = nil
        suspendedSensorAssociation = nil
        sensorProtectedFields.removeAll()
        lastSensorReceipt = nil
        lastSensorObservationTime = nil
    }

    /// A transport drop suspends the binding instead of ending it: ingestion
    /// authority is removed at once, while the operator's consent for this exact
    /// device/encounter/patient waits in memory for a reconnect. Protected vitals
    /// and the association's event fence survive; the operator is not re-asked.
    ///
    /// `associationID` is the current binding's `id`. A stale token does nothing,
    /// and repeating the call on an already-suspended binding is idempotent.
    public func suspendSensorAssociation(associationID: String, timestamp: Date = Date()) {
        // Idempotent: a repeated disconnect callback must not append a second
        // record, and must not cost the consent or its field protections.
        if suspendedSensorAssociation?.id == associationID { return }
        guard let association = sensorAssociation, association.id == associationID,
              timestamp.timeIntervalSince1970.isFinite else { return }
        settleProvisional()
        log.append(.sensorAssociation(.init(
            id: "sensor-suspension-" + UUID().uuidString, associationID: association.associationID,
            patientId: association.patientId, timestampUnix: timestamp.timeIntervalSince1970,
            deviceID: association.deviceID, deviceName: association.deviceName,
            connectionID: association.connectionID, encounterID: association.encounterID,
            eventFence: association.eventFence, kind: .suspended)))
        // Atomic within this actor turn: the retained binding carries consent only,
        // and nothing can ingest between dropping `sensorAssociation` and a resume.
        suspendedSensorAssociation = association
        sensorAssociation = nil
        lastSensorReceipt = nil
        lastSensorObservationTime = nil
    }

    /// Reconnect of the same device to the same encounter and patient resumes the
    /// suspended consent. This is not a new operator decision: the original
    /// consent chain, event fence and protected vitals are carried over.
    ///
    /// Returns a binding with a FRESH `id` bound to the new connection — callers
    /// must ingest with it, because the dropped connection's token is now dead.
    /// Anything that does not match exactly returns nil without mutating state,
    /// leaving the suspended consent intact for the correct reconnect.
    public func resumeSensorAssociation(associationID: String, deviceID: String,
        connectionID: UUID, encounterID: UUID, timestamp: Date = Date()) -> SensorAssociationPayload? {
        if #available(macOS 10.15, *) {
            guard !Task.isCancelled else { return nil }
        }
        guard sensorAssociation == nil,                       // never displace a live binding
              let suspended = suspendedSensorAssociation,
              suspended.id == associationID,
              suspended.deviceID == deviceID,
              suspended.encounterID == encounterID,
              suspended.connectionID != connectionID,         // the old link is gone
              suspended.patientId == currentPatientID,
              patients[suspended.patientId] != nil,
              timestamp.timeIntervalSince1970.isFinite else { return nil }
        settleProvisional()
        let resumed = SensorAssociationPayload(
            id: "sensor-resumption-" + UUID().uuidString, associationID: suspended.associationID,
            patientId: suspended.patientId, timestampUnix: timestamp.timeIntervalSince1970,
            deviceID: suspended.deviceID, deviceName: suspended.deviceName,
            connectionID: connectionID, encounterID: suspended.encounterID,
            eventFence: suspended.eventFence, kind: .resumed)
        log.append(.sensorAssociation(resumed))
        sensorAssociation = resumed
        suspendedSensorAssociation = nil
        // Ordering belongs to the new connection; the binding time is now, so
        // frames buffered during the outage are pre-association and cannot apply.
        // `sensorProtectedFields` and `sensorReadingIDs` deliberately survive.
        lastSensorReceipt = nil
        lastSensorObservationTime = nil
        return resumed
    }

    /// Record a bound sample and its exact applied deltas in one actor turn.
    /// Invalid identity/pre-association callbacks and duplicate sample IDs are
    /// discarded. Stale, unavailable, unsupported and protected data are audit
    /// evidence only. Unknown quality never becomes a claim of signal validity.
    public func recordSensorObservation(reading: PulseOximeterReading,
        waveforms: [PulseOximeterWaveform], associationID: String,
        connectionID: UUID, encounterID: UUID,
        auxiliaryFrames: [PulseOximeterRawFrame] = [],
        timestamp: Date = Date()) -> SensorObservationPayload? {
        if #available(macOS 10.15, *) {
            guard !Task.isCancelled else { return nil }
        }
        guard timestamp.timeIntervalSince1970.isFinite,
              reading.receivedAt.timeIntervalSince1970.isFinite,
              reading.acquiredAt?.timeIntervalSince1970.isFinite != false,
              reading.perfusionIndex?.isFinite != false,
              let association = sensorAssociation,
              association.id == associationID,
              association.connectionID == connectionID,
              association.encounterID == encounterID,
              association.patientId == currentPatientID,
              var patient = patients[association.patientId],
              reading.receivedAt.timeIntervalSince1970 >= association.timestampUnix,
              !sensorReadingIDs.contains(reading.id) else { return nil }

        settleProvisional()
        sensorReadingIDs.insert(reading.id)
        let observedAt = reading.acquiredAt ?? reading.receivedAt
        let receiptAge = timestamp.timeIntervalSince(reading.receivedAt)
        let observationAge = timestamp.timeIntervalSince(observedAt)
        let validTiming = timestamp.timeIntervalSince1970.isFinite
            && reading.receivedAt.timeIntervalSince1970.isFinite
            && observedAt.timeIntervalSince1970.isFinite
            && receiptAge >= 0 && observationAge >= 0
            && observedAt <= reading.receivedAt
        var deltas: [PatientStateDelta] = []
        var disposition: SensorObservationDisposition
        var protected: [SensorVitalField] = []

        if !validTiming {
            disposition = .invalidTiming
        } else if receiptAge > 5 || observationAge > 5
                    || observedAt.timeIntervalSince1970 < association.timestampUnix {
            disposition = .stale
        } else if lastSensorReceipt.map({ reading.receivedAt < $0 }) == true
                    || lastSensorObservationTime.map({ observedAt < $0 }) == true {
            disposition = .outOfOrder
        } else {
            lastSensorReceipt = reading.receivedAt
            lastSensorObservationTime = observedAt
            switch reading.quality {
            case .unavailable:
                disposition = .unavailable
            case .unsupportedEncoding:
                disposition = .unsupportedEncoding
            case .unknown:
                var hasUsableValue = false
                if let pulse = reading.pulseRate, (1...300).contains(pulse) {
                    hasUsableValue = true
                    if sensorProtectedFields.contains(.pulseRate) { protected.append(.pulseRate) }
                    else { deltas.append(.vitalsHR(pulse)) }
                }
                if let oxygen = reading.spo2, (1...100).contains(oxygen) {
                    hasUsableValue = true
                    if sensorProtectedFields.contains(.spo2) { protected.append(.spo2) }
                    else { deltas.append(.vitalsSpO2(oxygen)) }
                }
                if !hasUsableValue { disposition = .noUsableValues }
                else if deltas.isEmpty { disposition = .operatorProtected }
                else if !protected.isEmpty { disposition = .partiallyProtected }
                else { disposition = .recorded }
            }
        }

        if !deltas.isEmpty {
            let unix = observedAt.timeIntervalSince1970
            if patient.timestampFirstMention == nil { deltas.append(.timestampFirstMention(unix)) }
            deltas.append(.timestampLastUpdate(max(patient.timestampLastUpdate ?? unix, unix)))
        }
        let observation = SensorObservationPayload(id: "sensor-observation-" + reading.id.uuidString,
            patientId: association.patientId, timestampUnix: timestamp.timeIntervalSince1970,
            associationID: association.id, reading: reading,
            waveforms: waveforms.filter {
                $0.receivedAt.timeIntervalSince1970 >= association.timestampUnix
                    && $0.receivedAt <= reading.receivedAt
                    && reading.receivedAt.timeIntervalSince($0.receivedAt) <= 5
            },
            auxiliaryFrames: auxiliaryFrames.filter {
                $0.receivedAt.timeIntervalSince1970 >= association.timestampUnix
                    && $0.receivedAt <= reading.receivedAt
                    && reading.receivedAt.timeIntervalSince($0.receivedAt) <= 5
            },
            appliedDeltas: deltas, disposition: disposition, protectedFields: protected,
            reviewStatus: .unvalidatedConsumerSensor, units: SensorObservationUnits())
        log.append(.sensorObservation(observation))
        for delta in deltas { Self.applyDelta(delta, to: &patient) }
        patients[association.patientId] = patient
        return observation
    }

    /// Current HR/SpO2 provenance, resolving the latest actual writer per field.
    /// Later speech or operator writes remove that field's sensor origin; audit-
    /// only sensor frames and operator rejections do not change current values.
    public func sensorVitalOrigins(patientId: String = "PATIENT_1") -> [String: SensorObservationPayload] {
        var unresolved: Set<SensorVitalField> = [.pulseRate, .spo2]
        var origins: [String: SensorObservationPayload] = [:]
        for event in log.events.reversed() where event.patientId == patientId {
            guard !unresolved.isEmpty else { break }
            switch event {
            case .sensorObservation(let observation):
                for delta in observation.appliedDeltas {
                    guard let field = SensorVitalField.matching(delta),
                          unresolved.remove(field) != nil else { continue }
                    origins[field == .pulseRate ? "hr" : "spo2"] = observation
                }
            case .deterministicFact(let fact):
                if let field = SensorVitalField.matching(fact.delta) { unresolved.remove(field) }
            case .operatorAcceptedFact(let decision):
                if let write = decision.write, let field = SensorVitalField.matching(write) {
                    unresolved.remove(field)
                }
            case .asrSegment, .operatorRejectedFact, .lifecycle, .sensorAssociation:
                break
            }
        }
        return origins
    }

    /// Snapshot values and their current sensor sources in one actor turn so
    /// an intervening speech/operator write cannot label one snapshot with the
    /// provenance of a later snapshot.
    public func snapshotWithSensorOrigins(patientId: String = "PATIENT_1") -> (
        patients: [String: PatientState], sensorOrigins: [String: SensorObservationPayload],
        activeSensorAssociation: SensorAssociationPayload?,
        suspendedSensorAssociation: SensorAssociationPayload?
    ) {
        (patients, sensorVitalOrigins(patientId: patientId), sensorAssociation, suspendedSensorAssociation)
    }

    // MARK: - Internal helpers

    /// Emit the asrSegment + per-patient deterministicFact events for one transcript call.
    private func emitEvents(text: String, before: [String: PatientState], timestamp: Double, backend: String) {
        asrCount += 1
        let segId = "seg-\(asrCount)"
        log.append(.asrSegment(.init(
            id: segId, patientId: currentPatientID, timestampUnix: timestamp,
            text: text, backend: backend, isFinal: true)))
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
