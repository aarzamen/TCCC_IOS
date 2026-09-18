import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class WirelessSensorIntegrationTests: XCTestCase {
    private func observation(engine: PatientStateEngine, time: Date,
                             encounter: UUID = UUID()) async throws -> SensorObservationPayload {
        let connection = UUID()
        let binding = await engine.associateSensor(deviceID: "synthetic-unit", deviceName: "S5W synthetic",
            connectionID: connection, encounterID: encounter, timestamp: time)
        let association = try XCTUnwrap(binding)
        let reading = PulseOximeterReading(receivedAt: time, spo2: 96, pulseRate: 72,
            perfusionIndex: 2, rawFrame: Data([0xAA, 0x55]))
        let result = await engine.recordSensorObservation(reading: reading, waveforms: [],
            associationID: association.id, connectionID: connection, encounterID: encounter, timestamp: time)
        return try XCTUnwrap(result)
    }

    func testSavedOffSurvivesRelaunchWithoutStartingTransport() throws {
        let suite = "test-wireless-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = PulseOximeterBluetooth(defaults: defaults)
        XCTAssertTrue(initial.autoConnectEnabled)
        initial.setEnabled(false)
        initial.setEnabled(false)
        let restored = PulseOximeterBluetooth(defaults: defaults)
        restored.start()
        XCTAssertFalse(restored.autoConnectEnabled)
        XCTAssertEqual(restored.status, .disabled)
        XCTAssertNil(restored.connectionID)
        XCTAssertNil(restored.connectedDevice)
    }

    func testTransientDisconnectSuspendsConsentUntilExplicitStop() async throws {
        let state = AppState(wirelessSensors: WirelessSensorSession(transport: SyntheticPulseTransport()))
        state.startWirelessSensorsIfNeeded()
        let binding = await state.engine.associateSensor(deviceID: "synthetic-unit", deviceName: "Synthetic",
            connectionID: UUID(), encounterID: state.encounterIdentity)
        state.wirelessSensors.association = try XCTUnwrap(binding)
        state.wirelessSensors.transport.onSessionInvalidated?()
        await state.wirelessSensors.revocationTask?.value
        XCTAssertNil(state.wirelessSensors.association, "Old-connection ingestion must stop immediately")
        let suspendedLog = await state.engine.snapshotLog()
        let kinds = suspendedLog.events.compactMap { event -> String? in
            if case .sensorAssociation(let payload) = event { return payload.kind.rawValue }
            return nil
        }
        XCTAssertEqual(kinds, ["associated", "suspended"])

        await state.invalidateWirelessSensorAssociation()?.value
        let stoppedLog = await state.engine.snapshotLog()
        let stoppedKinds = stoppedLog.events.compactMap { event -> String? in
            if case .sensorAssociation(let payload) = event { return payload.kind.rawValue }
            return nil
        }
        XCTAssertEqual(stoppedKinds, ["associated", "suspended", "revoked"])
    }

    private func connectedSensor() async throws -> (AppState, SyntheticPulseTransport, URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport = SyntheticPulseTransport()
        let state = AppState(wirelessSensors: WirelessSensorSession(transport: transport))
        let store = EncounterStore(baseURL: base)
        try await store.startNewCasualty(id: "SYNTHETIC", startUnix: Date().timeIntervalSince1970)
        state.encounterStore = store
        state.startWirelessSensorsIfNeeded()
        transport.connect()
        await state.associateConnectedSensorWithCurrentEncounter()
        XCTAssertNotNil(state.wirelessSensors.association)
        return (state, transport, base)
    }

    func testSameSensorReconnectResumesRecordingWithoutAnotherTap() async throws {
        let (state, transport, base) = try await connectedSensor()
        defer { try? FileManager.default.removeItem(at: base) }
        let old = try XCTUnwrap(state.wirelessSensors.association)
        transport.sendReading()
        await state.wirelessSensors.ingestionTask?.value
        transport.disconnect()
        transport.connect()
        transport.sendReading()
        await state.wirelessSensors.resumeTask?.value
        let resumed = try XCTUnwrap(state.wirelessSensors.association)
        XCTAssertNotEqual(resumed.id, old.id)
        XCTAssertEqual(resumed.associationID, old.associationID)
        XCTAssertEqual(resumed.eventFence, old.eventFence)
        transport.sendReading()
        await state.wirelessSensors.ingestionTask?.value
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 62)
        XCTAssertEqual(state.primaryPatient?.vitals.spo2, 96)
        let log = await state.engine.snapshotLog()
        let recorded = log.events.compactMap { event -> SensorObservationPayload? in
            if case .sensorObservation(let observation) = event { return observation }
            return nil
        }
        XCTAssertEqual(recorded.count, 2)
        XCTAssertEqual(recorded.last?.associationID, resumed.id)
        // A delayed notification from the previous connection cannot enter.
        state.receiveWirelessData(SyntheticPulseTransport.frame, device: transport.device,
            connectionID: old.connectionID, receivedAt: Date())
        let afterStale = await state.engine.snapshotLog()
        XCTAssertEqual(afterStale.events.count, log.events.count)
        let stored = try await EncounterStore(baseURL: base).loadActiveEncounter()
        XCTAssertEqual(try XCTUnwrap(stored).log.events.count, log.events.count)
    }

    func testReconnectKeepsCorrectionsMadeBeforeAndDuringOutage() async throws {
        let (state, transport, base) = try await connectedSensor()
        defer { try? FileManager.default.removeItem(at: base) }
        await state.engine.recordOperatorAcceptedFact(write: .heartRate(88), factId: nil,
            domain: "vitals", field: "hr", rawValue: "88", to: "PATIENT_1")
        transport.disconnect()
        await state.wirelessSensors.revocationTask?.value
        await state.engine.recordOperatorAcceptedFact(write: .spo2(99), factId: nil,
            domain: "vitals", field: "spo2", rawValue: "99", to: "PATIENT_1")
        transport.connect()
        transport.sendReading()
        await state.wirelessSensors.resumeTask?.value
        transport.sendReading()
        await state.wirelessSensors.ingestionTask?.value
        XCTAssertEqual(state.primaryPatient?.vitals.hr, 88)
        XCTAssertEqual(state.primaryPatient?.vitals.spo2, 99)
        let log = await state.engine.snapshotLog()
        let sample = log.events.compactMap { event -> SensorObservationPayload? in
            if case .sensorObservation(let observation) = event { return observation }
            return nil
        }.last
        XCTAssertEqual(sample?.disposition, .operatorProtected)
    }

    func testDifferentSensorCannotInheritPausedAssociation() async throws {
        let (state, transport, base) = try await connectedSensor()
        defer { try? FileManager.default.removeItem(at: base) }
        transport.disconnect()
        transport.connect(deviceID: UUID())
        transport.sendReading()
        await state.wirelessSensors.revocationTask?.value
        XCTAssertNil(state.wirelessSensors.association)
        XCTAssertNil(state.wirelessSensors.resumableAssociation)
        let log = await state.engine.snapshotLog()
        XCTAssertFalse(log.events.contains { if case .sensorObservation = $0 { true } else { false } })
    }

    func testExplicitOffClearsPausedConsentAcrossReconnect() async throws {
        let (state, transport, base) = try await connectedSensor()
        defer { try? FileManager.default.removeItem(at: base) }
        transport.disconnect()
        state.setPulseOximeterAutoConnect(false)
        await state.wirelessSensors.revocationTask?.value
        state.setPulseOximeterAutoConnect(true)
        transport.connect()
        transport.sendReading()
        XCTAssertNil(state.wirelessSensors.association)
        XCTAssertNil(state.wirelessSensors.resumableAssociation)
        let snapshot = await state.engine.snapshotWithSensorOrigins()
        XCTAssertNil(snapshot.suspendedSensorAssociation)
        XCTAssertNil(snapshot.activeSensorAssociation)
    }

    func testSpokenPatientChangeClearsPausedAssociationImmediately() async throws {
        let (state, transport, base) = try await connectedSensor()
        defer { try? FileManager.default.removeItem(at: base) }
        transport.disconnect()
        await state.wirelessSensors.revocationTask?.value
        await state.refreshPatientSnapshot(persist: false, recordVitals: false)
        XCTAssertNotNil(state.wirelessSensors.resumableAssociation)
        await state.engine.processTranscript("patient two heart rate 90")
        await state.refreshPatientSnapshot(persist: false, recordVitals: false)
        XCTAssertNil(state.wirelessSensors.resumableAssociation)
        await state.wirelessSensors.revocationTask?.value
    }

    func testSensorColumnDoesNotRetimestampOtherVitalsAndExportsProvenance() async throws {
        let state = AppState()
        let time = Date(timeIntervalSince1970: 100)
        await state.engine.processTranscript("BP 120/80. Respiratory rate 20.", timestamp: time)
        let sample = try await observation(engine: state.engine, time: time)
        state.appendSensorReading(sample)
        let column = try XCTUnwrap(state.vitalsLog.first)
        XCTAssertEqual(column.timestamp, time)
        XCTAssertEqual(column.vitals.hr, 72)
        XCTAssertEqual(column.vitals.spo2, 96)
        XCTAssertNil(column.vitals.bp)
        XCTAssertNil(column.vitals.rr)
        XCTAssertNil(column.avpu)
        let csv = HandoffExports.vitalsCSV(readings: state.vitalsLog)
        XCTAssertTrue(csv.contains("pulse_oximeter,unvalidatedConsumerSensor,receipt"))
        XCTAssertFalse(csv.contains("synthetic-unit"))
        await state.refreshPatientSnapshot(persist: false, recordVitals: false)
        let data = HandoffQR.payload(for: state.primaryPatient, sensorProvenance: state.handoffSensorProvenance)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["sensorProvenance"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("synthetic-unit"))
        XCTAssertTrue(try XCTUnwrap(state.makeDD1380Card()).notes.contains("unvalidated consumer sensor"))
    }

    func testRecoveryRepairsGridFromEventsWithoutDroppingNewerManualReadings() async throws {
        let state = AppState()
        let time = Date(timeIntervalSince1970: 100)
        let sample = try await observation(engine: state.engine, time: time)
        let manual = AppState.SectionCReading(timestamp: Date(timeIntervalSince1970: 200),
            vitals: Vitals(hr: 80), avpu: nil)
        state.vitalsLog = [manual]
        let log = await state.engine.snapshotLog()
        state.recoverSensorReadings(from: log)
        state.recoverSensorReadings(from: log)
        XCTAssertEqual(state.vitalsLog.count, 2)
        XCTAssertEqual(state.vitalsLog.first?.id, sample.reading.id)
        XCTAssertEqual(state.vitalsLog.last?.id, manual.id)
        XCTAssertNil(state.wirelessSensors.association)
        let bytes = try AppState.sectionCCodec.encoder.encode(state.vitalsLog)
        let roundtrip = try AppState.sectionCCodec.decoder.decode([AppState.SectionCReading].self, from: bytes)
        XCTAssertEqual(roundtrip, state.vitalsLog)
    }

    func testContinuousStreamKeepsOperatorColumnsAndAllRawObservations() async throws {
        let state = AppState()
        let manual = (1...3).map { number in
            AppState.SectionCReading(timestamp: Date(timeIntervalSince1970: Double(number)),
                vitals: Vitals(bp: BloodPressure(systolic: 120, diastolic: 80)), avpu: nil)
        }
        state.vitalsLog = manual
        for offset in 0..<8 {
            let sample = try await observation(engine: state.engine,
                time: Date(timeIntervalSince1970: Double(100 + offset)))
            state.appendSensorReading(sample)
        }
        XCTAssertEqual(state.vitalsLog.count, 4)
        XCTAssertEqual(Array(state.vitalsLog.prefix(3)), manual)
        XCTAssertEqual(state.vitalsLog.last?.timestamp, Date(timeIntervalSince1970: 107))
        let log = await state.engine.snapshotLog()
        XCTAssertEqual(log.events.filter { if case .sensorObservation = $0 { true } else { false } }.count, 8)
        state.recoverSensorReadings(from: log)
        XCTAssertEqual(Array(state.vitalsLog.prefix(3)), manual)
        XCTAssertEqual(state.vitalsLog.count, 4)
    }

    func testLegacySectionCWithoutSourceStillDecodes() throws {
        let reading = AppState.SectionCReading(timestamp: .distantPast, vitals: Vitals(hr: 80), avpu: nil)
        let encoder = AppState.sectionCCodec.encoder
        let data = try encoder.encode(reading)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "sensorSource")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try AppState.sectionCCodec.decoder.decode(AppState.SectionCReading.self, from: legacy)
        XCTAssertNil(decoded.sensorSource)
        XCTAssertEqual(decoded.vitals.hr, 80)
    }

    func testOldDirectoryCannotReceiveQueuedSensorEvidenceAfterRotation() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let store = EncounterStore(baseURL: base)
        try await store.startNewCasualty(id: "OLD", startUnix: 1)
        let oldDirectory = await store.activeDirectoryName()
        let directory = try XCTUnwrap(oldDirectory)
        let engine = PatientStateEngine.standard()
        let sample = try await observation(engine: engine, time: Date(timeIntervalSince1970: 100))
        try await store.archiveActive(endedUnix: 2)
        try await store.startNewCasualty(id: "NEW", startUnix: 2)
        do {
            try await store.appendToActive([.sensorObservation(sample)], expectedDirectory: directory)
            XCTFail("The old sensor drain must not write into the new directory")
        } catch { }
        let restored = try await EncounterStore(baseURL: base).loadActiveEncounter()
        XCTAssertTrue(try XCTUnwrap(restored).log.events.isEmpty)
    }

    func testSnapshotReconcilesAssociationRevokedBySpokenPatientSwitch() async throws {
        let state = AppState()
        let binding = await state.engine.associateSensor(deviceID: "synthetic-unit", deviceName: "Synthetic",
            connectionID: UUID(), encounterID: state.encounterIdentity)
        state.wirelessSensors.association = try XCTUnwrap(binding)
        await state.engine.processTranscript("patient two heart rate 90")
        await state.refreshPatientSnapshot(persist: false, recordVitals: false)
        XCTAssertNil(state.wirelessSensors.association)
        XCTAssertNotNil(state.wirelessSensors.message)
        await state.wirelessSensors.revocationTask?.value
    }

    func testStaleSnapshotCannotInvalidateNewerAssociation() async throws {
        let state = AppState()
        let oldGeneration = state.wirelessSensors.generation
        let old = await state.engine.associateSensor(deviceID: "synthetic-unit", deviceName: "Synthetic",
            connectionID: UUID(), encounterID: state.encounterIdentity)
        let oldBinding = try XCTUnwrap(old)
        let new = await state.engine.associateSensor(deviceID: "synthetic-unit", deviceName: "Synthetic",
            connectionID: UUID(), encounterID: state.encounterIdentity)
        let newBinding = try XCTUnwrap(new)
        state.wirelessSensors.association = newBinding
        state.wirelessSensors.generation = UUID()
        state.reconcileWirelessSensorAssociation(activeAssociation: nil,
            expectedAssociationID: oldBinding.id, generation: oldGeneration)
        XCTAssertEqual(state.wirelessSensors.association?.id, newBinding.id)
        let snapshot = await state.engine.snapshotWithSensorOrigins()
        XCTAssertEqual(snapshot.activeSensorAssociation?.id, newBinding.id)
    }

    func testEachLifecycleTransitionIsGatedBeforeAwaitAndReleasedAfterCompletion() async {
        for action in 0..<3 {
            let state = AppState()
            let gate = WirelessTransitionGate()
            state.wirelessSensors.revocationTask = Task { await gate.wait() }
            let previousEncounter = state.encounterIdentity
            let transition = Task { @MainActor in
                switch action {
                case 0: await state.newPatient()
                case 1: await state.endCurrentCare()
                default: await state.wipeSession()
                }
            }
            for _ in 0..<100 where !state.wirelessSensors.encounterTransitionInProgress {
                await Task.yield()
            }
            XCTAssertTrue(state.wirelessSensors.encounterTransitionInProgress)
            XCTAssertEqual(state.encounterIdentity, previousEncounter)
            await gate.open()
            await transition.value
            XCTAssertFalse(state.wirelessSensors.encounterTransitionInProgress)
            XCTAssertNotEqual(state.encounterIdentity, previousEncounter)
            XCTAssertNil(state.wirelessSensors.association)
        }
    }

    func testInvalidationCancelsEarlierIngestionAndTailBeforeBarrierResumes() async {
        let state = AppState()
        let gate = WirelessTransitionGate()
        var firstWasCanceled = false
        var tailWasCanceled = false
        let first = Task { @MainActor in
            await gate.wait()
            firstWasCanceled = Task.isCancelled
        }
        let tail = Task { @MainActor in
            await first.value
            tailWasCanceled = Task.isCancelled
        }
        state.wirelessSensors.ingestionTasks[UUID()] = first
        state.wirelessSensors.ingestionTasks[UUID()] = tail
        state.wirelessSensors.ingestionTask = tail

        let drain = state.invalidateWirelessSensorAssociation()
        await gate.open()
        await tail.value
        await drain?.value

        XCTAssertTrue(firstWasCanceled,
            "Canceling only the tail leaves an earlier actor-bound ingestion task live")
        XCTAssertTrue(tailWasCanceled)
    }
}

/// Only the radio is substituted; parsing, association, event ingestion and
/// protected storage above all use their real production implementations.
@MainActor
private final class SyntheticPulseTransport: PulseOximeterTransport {
    static let frame = Data([0xAA, 0x55, 0x0F, 0x08, 0x01, 0x60, 0x3E, 0x00, 0x50, 0x00, 0xC0, 0x08])
    var device = PulseOximeterBluetooth.Device(id: UUID(), name: "S5W synthetic")
    var status: PulseOximeterBluetooth.Status = .disconnected
    var devices: [PulseOximeterBluetooth.Device] { [device] }
    var connectedDevice: PulseOximeterBluetooth.Device?
    var connectionID: UUID?
    var autoConnectEnabled = true
    var onNotification: (@MainActor (Data, PulseOximeterBluetooth.Device, UUID, Date) -> Void)?
    var onSessionInvalidated: (@MainActor () -> Void)?
    func start() {}
    func setEnabled(_ enabled: Bool) {
        autoConnectEnabled = enabled
        if !enabled { disconnect() }
    }
    func selectDevice(_ id: UUID) {}
    func applicationDidBecomeActive() {}
    func applicationDidEnterBackground() {}
    func markValidReadingReceived(connectionID: UUID) { status = .receiving }
    func markReadingUnavailable(connectionID: UUID) { status = .connectedAwaitingData }
    func connect(deviceID: UUID? = nil) {
        if let deviceID { device = .init(id: deviceID, name: "S5W other synthetic") }
        connectedDevice = device
        connectionID = UUID()
        status = .connectedAwaitingData
    }
    func disconnect() {
        connectedDevice = nil
        connectionID = nil
        status = .disconnected
        onSessionInvalidated?()
    }
    func sendReading() {
        guard let connectionID else { return }
        onNotification?(Self.frame, device, connectionID, Date())
    }
}

private actor WirelessTransitionGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
