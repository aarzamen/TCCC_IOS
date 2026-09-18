import Foundation
import XCTest
import TCCCDomain
@testable import TCCCExtractor

final class SensorEvidenceTests: XCTestCase {
    private let connection = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let encounter = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private func date(_ time: Double) -> Date { Date(timeIntervalSince1970: time) }

    private func reading(id: UUID = UUID(), time: Double = 102,
                         acquired: Double? = nil, spo2: Int? = 97, pulse: Int? = 81,
                         quality: PulseOximeterQuality = .unknown) -> PulseOximeterReading {
        PulseOximeterReading(id: id, receivedAt: date(time), acquiredAt: acquired.map(date),
            spo2: spo2, pulseRate: pulse, perfusionIndex: 2.5,
            rawFrame: Data([0x53, 0x59, 0x4e, 0x54, 0x48]),
            protocolVersion: "synthetic-test-v1", quality: quality)
    }

    private func bind(_ engine: PatientStateEngine, time: Double = 100) async throws -> SensorAssociationPayload {
        let binding = await engine.associateSensor(deviceID: "synthetic-device", deviceName: "Synthetic oximeter",
            connectionID: connection, encounterID: encounter, timestamp: date(time))
        return try XCTUnwrap(binding)
    }

    private func ingest(_ sample: PulseOximeterReading, engine: PatientStateEngine,
                        binding: SensorAssociationPayload, now: Double = 103,
                        waveforms: [PulseOximeterWaveform] = []) async -> SensorObservationPayload? {
        await engine.recordSensorObservation(reading: sample, waveforms: waveforms,
            associationID: binding.id, connectionID: connection, encounterID: encounter,
            timestamp: date(now))
    }

    func testBoundUnknownQualityNumericReadingRetainsEvidenceAndReplaysExactly() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        let sample = reading()
        let waveform = PulseOximeterWaveform(receivedAt: date(101),
            rawFrame: Data([0x01, 0x02, 0x03]), samples: [1, 2, 3])
        let result = await ingest(sample, engine: engine, binding: binding, waveforms: [waveform])
        let observation = try XCTUnwrap(result)
        XCTAssertEqual(observation.reading, sample)
        XCTAssertEqual(observation.waveforms, [waveform])
        XCTAssertEqual(observation.reviewStatus, .unvalidatedConsumerSensor)
        XCTAssertEqual(observation.disposition, .recorded)
        XCTAssertEqual(observation.observationTime, date(102))
        XCTAssertEqual(observation.timeBasis, .receipt)
        XCTAssertEqual(observation.units.pulseRate, .beatsPerMinute)
        XCTAssertEqual(observation.units.spo2, .percent)
        XCTAssertTrue(observation.appliedDeltas.contains(.vitalsHR(81)))
        XCTAssertTrue(observation.appliedDeltas.contains(.vitalsSpO2(97)))
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot["PATIENT_1"]?.vitals, Vitals(hr: 81, spo2: 97))
        XCTAssertEqual(snapshot["PATIENT_1"]?.timestampLastUpdate, 102)
        let log = await engine.snapshotLog()
        let decoded = try JSONDecoder().decode(EncounterLog.self, from: JSONEncoder().encode(log))
        XCTAssertEqual(decoded, log)
        XCTAssertEqual(PatientStateEngine.project(decoded), snapshot)
        XCTAssertTrue(PatientStateEngine.deterministicFacts(from: log).isEmpty,
            "Sensor readings must not become high-confidence speech facts")
    }

    func testUnavailableUnsupportedAndZeroValuesNeverClearKnownVitals() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        _ = await ingest(reading(), engine: engine, binding: binding)
        for (quality, want) in [
            (PulseOximeterQuality.unavailable, SensorObservationDisposition.unavailable),
            (.unsupportedEncoding, .unsupportedEncoding)
        ] {
            let result = await ingest(reading(time: 103, spo2: 99, pulse: 120, quality: quality),
                engine: engine, binding: binding, now: 104)
            XCTAssertEqual(result?.disposition, want)
            XCTAssertEqual(result?.appliedDeltas, [])
        }
        let zeros = await ingest(reading(time: 104, spo2: 0, pulse: 0),
            engine: engine, binding: binding, now: 105)
        XCTAssertEqual(zeros?.disposition, .noUsableValues)
        XCTAssertEqual(zeros?.appliedDeltas, [])
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals, Vitals(hr: 81, spo2: 97))
    }

    func testOneValidFieldIsRecordedWithoutInventingOtherFields() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        let result = await ingest(reading(spo2: 101, pulse: 88), engine: engine, binding: binding)
        let observation = try XCTUnwrap(result)
        XCTAssertTrue(observation.appliedDeltas.contains(.vitalsHR(88)))
        XCTAssertFalse(observation.appliedDeltas.contains { if case .vitalsSpO2 = $0 { return true }; return false })
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals, Vitals(hr: 88))
    }

    func testWrongAssociationConnectionEncounterAndPreBindingReadingsAreIgnored() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        let sample = reading()
        for (associationID, connectionID, encounterID) in [
            ("old-association", connection, encounter),
            (binding.id, UUID(), encounter),
            (binding.id, connection, UUID())
        ] {
            let result = await engine.recordSensorObservation(reading: sample, waveforms: [],
                associationID: associationID, connectionID: connectionID, encounterID: encounterID,
                timestamp: date(103))
            XCTAssertNil(result)
        }
        let prior = await ingest(reading(time: 99), engine: engine, binding: binding)
        XCTAssertNil(prior)
        let snapshot = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(snapshot?.vitals, Vitals())
        let log = await engine.snapshotLog()
        XCTAssertEqual(log.events.count, 2, "Rejected callback identities must not acquire clinical provenance")
    }

    func testDuplicateSampleIgnoredButIdenticalNewSampleRetainsItsOwnTime() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        let sample = reading()
        _ = await ingest(sample, engine: engine, binding: binding)
        let duplicate = await ingest(sample, engine: engine, binding: binding)
        XCTAssertNil(duplicate)
        let next = await ingest(reading(time: 104), engine: engine, binding: binding, now: 104)
        XCTAssertEqual(next?.observationTime, date(104))
        XCTAssertTrue(next?.appliedDeltas.contains(.vitalsHR(81)) == true,
            "An unchanged value is still a new timed measurement")
    }

    func testStaleAndOutOfOrderSamplesAreEvidenceOnly() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        _ = await ingest(reading(time: 104), engine: engine, binding: binding, now: 105)
        let late = await ingest(reading(time: 103, pulse: 160), engine: engine, binding: binding, now: 105)
        XCTAssertEqual(late?.disposition, .outOfOrder)
        XCTAssertEqual(late?.appliedDeltas, [])
        let stale = await ingest(reading(time: 106, pulse: 170), engine: engine, binding: binding, now: 112)
        XCTAssertEqual(stale?.disposition, .stale)
        XCTAssertEqual(stale?.appliedDeltas, [])
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals.hr, 81)
        XCTAssertEqual(patient?.timestampLastUpdate, 104)
    }

    func testAcquisitionTimeWhenAvailableIsDistinctAndCannotBeFuture() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        let observed = await ingest(reading(acquired: 101), engine: engine, binding: binding)
        XCTAssertEqual(observed?.observationTime, date(101))
        XCTAssertEqual(observed?.reading.receivedAt, date(102))
        XCTAssertEqual(observed?.timeBasis, .deviceAcquisition)
        let impossible = await ingest(reading(time: 104, acquired: 105, pulse: 150),
            engine: engine, binding: binding, now: 104)
        XCTAssertEqual(impossible?.disposition, .invalidTiming)
        XCTAssertEqual(impossible?.appliedDeltas, [])
    }

    func testTypedOperatorCorrectionAfterBindingProtectsOnlyThatVitalUntilRebind() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        await engine.recordOperatorAcceptedFact(write: .heartRate(70), factId: nil,
            domain: "manual", field: "operator entry", rawValue: nil, to: "PATIENT_1", timestamp: date(101))
        let result = await ingest(reading(), engine: engine, binding: binding)
        XCTAssertEqual(result?.disposition, .partiallyProtected)
        XCTAssertFalse(result?.appliedDeltas.contains(.vitalsHR(81)) == true)
        var patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals, Vitals(hr: 70, spo2: 97))
        let rebound = try await bind(engine, time: 104)
        _ = await ingest(reading(time: 105, pulse: 82), engine: engine, binding: rebound, now: 105)
        patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals.hr, 82)
    }

    func testOperatorRejectionAliasesProtectVitalsWithoutBlockingOtherPatientDecisions() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        await engine.recordOperatorRejectedFact(factId: nil, domain: "vitals", field: "SpO₂",
            rawValue: "97", to: "PATIENT_1", timestamp: date(101))
        await engine.recordOperatorAcceptedFact(write: .heartRate(50), factId: nil,
            domain: "manual", field: "operator entry", rawValue: nil, to: "PATIENT_2", timestamp: date(101))
        let first = await ingest(reading(), engine: engine, binding: binding)
        XCTAssertEqual(first?.disposition, .partiallyProtected)
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals, Vitals(hr: 81))
        await engine.recordOperatorRejectedFact(factId: nil, domain: "vitals", field: "pulseRate",
            rawValue: "81", to: "PATIENT_1", timestamp: date(103))
        let second = await ingest(reading(time: 104), engine: engine, binding: binding, now: 104)
        XCTAssertEqual(second?.disposition, .operatorProtected)
        XCTAssertEqual(second?.appliedDeltas, [])
    }

    func testOldDisconnectDoesNotRevokeNewBindingAndRevocationRejectsQueuedReadings() async throws {
        let engine = PatientStateEngine.standard()
        let old = try await bind(engine)
        let current = try await bind(engine, time: 101)
        await engine.revokeSensorAssociation(associationID: old.id, timestamp: date(102))
        let result = await ingest(reading(), engine: engine, binding: current)
        XCTAssertNotNil(result)
        await engine.revokeSensorAssociation(associationID: current.id, timestamp: date(103))
        let delayed = await ingest(reading(time: 104), engine: engine, binding: current, now: 104)
        XCTAssertNil(delayed)
    }

    func testSensorAppendSettlesProvisionalTailSoRevisionCannotRemoveEvidence() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        await engine.commitProvisional("respiratory rate 20", timestamp: date(101))
        let observation = await ingest(reading(), engine: engine, binding: binding)
        let count = await engine.snapshotLog().events.count
        await engine.reviseProvisional("respiratory rate 30", timestamp: date(104))
        let log = await engine.snapshotLog()
        let snapshot = await engine.snapshot()
        XCTAssertEqual(log.events.count, count)
        XCTAssertTrue(log.events.contains { $0.id == observation?.id })
        XCTAssertEqual(snapshot["PATIENT_1"]?.vitals.rr, 20)
        XCTAssertEqual(PatientStateEngine.project(log), snapshot)
    }

    func testRestorePreservesRecordedDeltasButRequiresNewAssociation() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        _ = await ingest(reading(), engine: engine, binding: binding)
        await engine.recordOperatorAcceptedFact(write: .heartRate(65), factId: nil,
            domain: "manual", field: "operator entry", rawValue: nil, to: "PATIENT_1", timestamp: date(104))
        let log = await engine.snapshotLog()
        let replay = PatientStateEngine.standard()
        await replay.restore(log)
        let resumedOldConnection = await ingest(reading(time: 105), engine: replay, binding: binding, now: 105)
        XCTAssertNil(resumedOldConnection)
        let snapshot = await replay.snapshot(of: "PATIENT_1")
        XCTAssertEqual(snapshot?.vitals, Vitals(hr: 65, spo2: 97))
        let newBinding = try await bind(replay, time: 105)
        _ = await ingest(reading(time: 106, pulse: 83), engine: replay, binding: newBinding, now: 106)
        let finalSnapshot = await replay.snapshot()
        let finalLog = await replay.snapshotLog()
        XCTAssertEqual(finalSnapshot["PATIENT_1"]?.vitals.hr, 83)
        XCTAssertEqual(PatientStateEngine.project(finalLog), finalSnapshot)
    }

    func testOldLogWithoutSensorCasesStillRestoresAndSensorStartsUnbound() async throws {
        let oldJSON = #"{"events":[{"lifecycle":{"_0":{"id":"lc-1","patientId":"PATIENT_1","timestampUnix":0,"kind":"encounterStarted"}}},{"deterministicFact":{"_0":{"id":"fact-1","patientId":"PATIENT_1","timestampUnix":90,"delta":{"vitalsHR":{"_0":75}},"evidenceIds":["seg-1"],"extractor":"deterministic"}}}]}"#
        let log = try JSONDecoder().decode(EncounterLog.self, from: Data(oldJSON.utf8))
        let engine = PatientStateEngine.standard()
        await engine.restore(log)
        let result = await engine.recordSensorObservation(reading: reading(), waveforms: [],
            associationID: "unbound", connectionID: connection, encounterID: encounter, timestamp: date(103))
        XCTAssertNil(result)
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals.hr, 75)
    }

    func testOriginsTrackCurrentWriterPerVitalAndIgnoreUnavailableEvidence() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        let sensor = await ingest(reading(), engine: engine, binding: binding)
        var origins = await engine.sensorVitalOrigins()
        XCTAssertEqual(origins["hr"]?.id, sensor?.id)
        XCTAssertEqual(origins["spo2"]?.id, sensor?.id)
        _ = await ingest(reading(time: 103, quality: .unavailable),
            engine: engine, binding: binding, now: 104)
        origins = await engine.sensorVitalOrigins()
        XCTAssertEqual(origins["hr"]?.id, sensor?.id)
        await engine.recordOperatorAcceptedFact(write: .heartRate(69), factId: nil,
            domain: "manual", field: "operator entry", rawValue: nil, to: "PATIENT_1", timestamp: date(104))
        origins = await engine.sensorVitalOrigins()
        XCTAssertNil(origins["hr"])
        XCTAssertEqual(origins["spo2"]?.id, sensor?.id)
        await engine.processTranscript("spo2 95", timestamp: date(105))
        origins = await engine.sensorVitalOrigins()
        XCTAssertTrue(origins.isEmpty)
    }

    func testPersistenceOnlyExposesPermanentEventsWhileNewSpeechIsProvisional() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        _ = await ingest(reading(), engine: engine, binding: binding)
        let permanent = await engine.snapshotLog().events
        await engine.commitProvisional("respiratory rate 20", timestamp: date(104))
        let safeToPersist = await engine.persistableEvents(since: 0)
        XCTAssertEqual(safeToPersist, permanent)
        let none = await engine.persistableEvents(since: permanent.count)
        XCTAssertTrue(none.isEmpty)
        await engine.reviseProvisional("respiratory rate 30", timestamp: date(105))
        await engine.settleProvisional()
        let settled = await engine.persistableEvents(since: permanent.count)
        var diskLog = EncounterLog(events: permanent)
        for event in settled { diskLog.append(event) }
        let snapshot = await engine.snapshot()
        XCTAssertEqual(snapshot["PATIENT_1"]?.vitals.rr, 30)
        XCTAssertEqual(PatientStateEngine.project(diskLog), snapshot)
    }

    func testHiddenPatientCannotBeBoundAndSwitchingBackDoesNotReviveOldBinding() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        await engine.processTranscript("patient two heart rate 90", timestamp: date(101))
        let mismatch = await engine.associateSensor(deviceID: "synthetic-device", deviceName: "Synthetic",
            connectionID: connection, encounterID: encounter, timestamp: date(102))
        XCTAssertNil(mismatch)
        let other = await ingest(reading(), engine: engine, binding: binding)
        XCTAssertNil(other)
        await engine.processTranscript("patient one airway patent", timestamp: date(104))
        let previous = await ingest(reading(time: 105), engine: engine, binding: binding, now: 105)
        XCTAssertNil(previous)
    }

    func testEndingEncounterRevokesSensorBeforeMoreReadingsCanArrive() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        await engine.recordLifecycle(.encounterEnded, timestamp: date(101))
        let result = await ingest(reading(), engine: engine, binding: binding)
        XCTAssertNil(result)
    }

    func testNonfiniteTimingIsRejectedBeforeItCanPoisonJSONPersistence() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        let invalidAcquisition = await ingest(reading(acquired: .nan), engine: engine, binding: binding)
        XCTAssertNil(invalidAcquisition)
        let invalidIngestion = await ingest(reading(), engine: engine, binding: binding, now: .infinity)
        XCTAssertNil(invalidIngestion)
        let log = await engine.snapshotLog()
        XCTAssertEqual(log.events.count, 2)
        XCTAssertNoThrow(try JSONEncoder().encode(log))
    }

    func testPatientSwitchInsideProvisionalCannotEraseAssociationRevocation() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        await engine.commitProvisional("patient two heart rate 90", timestamp: date(101))
        await engine.reviseProvisional("patient one heart rate 91", timestamp: date(102))
        let log = await engine.snapshotLog()
        let revocations = log.events.compactMap { event -> SensorAssociationPayload? in
            if case .sensorAssociation(let association) = event,
               association.kind == .revoked, association.associationID == binding.id { return association }
            return nil
        }
        XCTAssertEqual(revocations.count, 1, "Revisable speech cannot remove a connection-ownership decision")
        let snapshot = await engine.snapshot()
        XCTAssertEqual(PatientStateEngine.project(log), snapshot)
        let result = await ingest(reading(time: 103), engine: engine, binding: binding)
        XCTAssertNil(result)
    }

    func testCanceledIngestionCannotAppendEvidenceOrMutateVitals() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        let sample = reading()
        let connectionID = connection, encounterID = encounter, now = date(103)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await engine.recordSensorObservation(reading: sample, waveforms: [],
                associationID: binding.id, connectionID: connectionID, encounterID: encounterID, timestamp: now)
        }
        let observation = await task.value
        XCTAssertNil(observation)
        let log = await engine.snapshotLog()
        XCTAssertEqual(log.events.count, 2)
        let patient = await engine.snapshot(of: "PATIENT_1")
        XCTAssertEqual(patient?.vitals, Vitals())
    }

    func testAuxiliaryFramesRetainRawEvidenceWithinAssociationAndReceiptWindow() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        let accepted = PulseOximeterRawFrame(receivedAt: date(105), rawFrame: Data([1, 2, 3]))
        let frames = [
            PulseOximeterRawFrame(receivedAt: date(99), rawFrame: Data([4])), // before association
            PulseOximeterRawFrame(receivedAt: date(101), rawFrame: Data([5])), // too old
            accepted,
            PulseOximeterRawFrame(receivedAt: date(109), rawFrame: Data([6])), // after reading
        ]
        let result = await engine.recordSensorObservation(reading: reading(time: 108), waveforms: [],
            associationID: binding.id, connectionID: connection, encounterID: encounter,
            auxiliaryFrames: frames, timestamp: date(108))
        let observation = try XCTUnwrap(result)
        XCTAssertEqual(observation.auxiliaryFrames, [accepted])
        let encoded = try JSONEncoder().encode(observation)
        let decoded = try JSONDecoder().decode(SensorObservationPayload.self, from: encoded)
        XCTAssertEqual(decoded, observation)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        old.removeValue(forKey: "auxiliaryFrames")
        let oldDecoded = try JSONDecoder().decode(SensorObservationPayload.self,
            from: JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue((oldDecoded.auxiliaryFrames ?? []).isEmpty)
        XCTAssertEqual(oldDecoded.appliedDeltas, observation.appliedDeltas)
        let snapshot = await engine.snapshot()
        let log = await engine.snapshotLog()
        XCTAssertEqual(snapshot, PatientStateEngine.project(log))
    }

    func testAtomicSnapshotReportsBindingRevokedByPatientSwitch() async throws {
        let engine = PatientStateEngine.standard()
        let binding = try await bind(engine)
        let before = await engine.snapshotWithSensorOrigins()
        XCTAssertEqual(before.activeSensorAssociation?.id, binding.id)
        await engine.processTranscript("patient two heart rate 90", timestamp: date(101))
        let after = await engine.snapshotWithSensorOrigins()
        XCTAssertNil(after.activeSensorAssociation)
        XCTAssertEqual(after.patients["PATIENT_2"]?.vitals.hr, 90)
    }
}
