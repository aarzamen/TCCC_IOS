import Foundation
import Observation
import TCCCDomain
import TCCCExtractor

/// Derived display/export metadata. Raw device identity and frames stay in the
/// protected encounter events rather than the ordinary CSV/QR handoff.
struct SensorReadingSource: Codable, Hashable, Sendable {
    let observationID: String
    let timeBasis: String
    let reviewStatus: String
    var receivedAt: Date? = nil
    var label: String { "Pulse oximeter · unvalidated" }
}

@MainActor @Observable
final class WirelessSensorSession {
    let transport: PulseOximeterBluetooth
    var preview: PulseOximeterReading?
    var association: SensorAssociationPayload?
    var message: String?
    var bindingInProgress = false
    var encounterTransitionInProgress = false
    var configured = false
    var generation = UUID()
    var directory: String?
    var decoder = LepuPulseOximeterDecoder()
    var waveforms: [PulseOximeterWaveform] = []
    var auxiliaryFrames: [PulseOximeterRawFrame] = []
    var ingestionTask: Task<Void, Never>?
    var ingestionTasks: [UUID: Task<Void, Never>] = [:]
    var revocationTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        transport = PulseOximeterBluetooth(defaults: defaults)
    }

    var previewIsFresh: Bool {
        guard let preview, preview.quality == .unknown,
              preview.spo2 != nil, preview.pulseRate != nil else { return false }
        return Date().timeIntervalSince(preview.receivedAt) <= 5
            && transport.connectionID != nil && transport.autoConnectEnabled
    }
}

extension AppState {
    var handoffSensorProvenance: [String: SensorReadingSource] {
        sensorVitalOrigins.mapValues { observation in
            SensorReadingSource(observationID: observation.id, timeBasis: observation.timeBasis.rawValue,
                reviewStatus: observation.reviewStatus.rawValue, receivedAt: observation.reading.receivedAt)
        }
    }

    func startWirelessSensorsIfNeeded() {
        guard !wirelessSensors.configured else { return }
        wirelessSensors.configured = true
        wirelessSensors.transport.onNotification = { [weak self] data, device, connection, time in
            self?.receiveWirelessData(data, device: device, connectionID: connection, receivedAt: time)
        }
        wirelessSensors.transport.onSessionInvalidated = { [weak self] in
            guard let self else { return }
            self.invalidateWirelessSensorAssociation(clearPreview: true)
            self.wirelessSensors.decoder.reset()
        }
        wirelessSensors.transport.start()
    }

    func setPulseOximeterAutoConnect(_ enabled: Bool) {
        if !enabled { invalidateWirelessSensorAssociation(clearPreview: true) }
        wirelessSensors.transport.setEnabled(enabled)
    }

    /// Invalidate synchronously before the first lifecycle await. A queued old
    /// callback keeps its original engine and can never target the new casualty.
    @discardableResult
    func invalidateWirelessSensorAssociation(clearPreview: Bool = false) -> Task<Void, Never>? {
        let session = wirelessSensors
        session.generation = UUID()
        let binding = session.association
        session.association = nil
        session.directory = nil
        session.bindingInProgress = false
        let pendingIngestions = Array(session.ingestionTasks.values)
        session.ingestionTasks.removeAll()
        for task in pendingIngestions { task.cancel() }
        session.ingestionTask?.cancel()
        let drain = session.ingestionTask
        session.ingestionTask = nil
        session.waveforms.removeAll()
        session.auxiliaryFrames.removeAll()
        if clearPreview {
            session.preview = nil
            session.decoder.reset()
        }
        guard binding != nil || drain != nil || !pendingIngestions.isEmpty else { return session.revocationTask }
        let origin = engine
        let encounter = encounterIdentity
        let priorRevocation = session.revocationTask
        let task = Task { @MainActor [weak self] in
            await priorRevocation?.value
            await drain?.value
            for task in pendingIngestions { await task.value }
            guard let binding else { return }
            await origin.revokeSensorAssociation(associationID: binding.id)
            guard let self, self.engine === origin, self.encounterIdentity == encounter else { return }
            await self.persistNewEvents()
        }
        session.revocationTask = task
        return task
    }

    func associateConnectedSensorWithCurrentEncounter() async {
        let session = wirelessSensors
        guard !Task.isCancelled, !session.encounterTransitionInProgress,
              !session.bindingInProgress, session.transport.autoConnectEnabled,
              let device = session.transport.connectedDevice,
              let connection = session.transport.connectionID,
              let store = encounterStore else { return }
        let stop = invalidateWirelessSensorAssociation()
        session.bindingInProgress = true
        let generation = session.generation
        defer {
            if session.generation == generation { session.bindingInProgress = false }
        }
        let encounter = encounterIdentity
        let origin = engine
        await stop?.value
        guard !Task.isCancelled, !session.encounterTransitionInProgress,
              session.generation == generation, encounterIdentity == encounter,
              engine === origin, session.transport.connectionID == connection else { return }
        await settleCaptureBeforeOperatorEntry()
        guard !Task.isCancelled, !session.encounterTransitionInProgress,
              session.generation == generation, encounterIdentity == encounter,
              engine === origin, session.transport.connectionID == connection else { return }
        let directory = await store.activeDirectoryName()
        guard let directory, !Task.isCancelled, !session.encounterTransitionInProgress,
              session.generation == generation, encounterIdentity == encounter,
              engine === origin, session.transport.connectionID == connection else { return }
        guard let binding = await origin.associateSensor(deviceID: device.id.uuidString,
            deviceName: device.name, connectionID: connection, encounterID: encounter) else {
            guard session.generation == generation, encounterIdentity == encounter,
                  engine === origin, !session.encounterTransitionInProgress else { return }
            session.bindingInProgress = false
            session.message = "Association unavailable: displayed casualty differs from the active engine casualty."
            return
        }
        guard !Task.isCancelled, !session.encounterTransitionInProgress,
              session.generation == generation, encounterIdentity == encounter,
              engine === origin, session.transport.connectionID == connection else {
            await origin.revokeSensorAssociation(associationID: binding.id)
            return
        }
        session.association = binding
        session.directory = directory
        session.bindingInProgress = false
        session.message = nil
        await persistNewEvents()
    }

    /// A snapshot may resume after a new operator association. Reconcile only
    /// the local binding and generation captured before that snapshot await.
    func reconcileWirelessSensorAssociation(activeAssociation: SensorAssociationPayload?,
                                            expectedAssociationID: String?, generation: UUID) {
        let session = wirelessSensors
        guard let expectedAssociationID, session.generation == generation,
              session.association?.id == expectedAssociationID,
              activeAssociation?.id != expectedAssociationID else { return }
        invalidateWirelessSensorAssociation()
        session.message = "Sensor association ended. Confirm the current casualty before recording again."
    }

    func receiveWirelessData(_ data: Data, device: PulseOximeterBluetooth.Device,
                             connectionID: UUID, receivedAt: Date) {
        let session = wirelessSensors
        guard session.transport.autoConnectEnabled,
              session.transport.connectionID == connectionID,
              session.transport.connectedDevice?.id == device.id else { return }
        for packet in session.decoder.append(data, receivedAt: receivedAt) {
            switch packet {
            case .waveform(let frame):
                session.waveforms.append(frame)
                session.waveforms = Array(session.waveforms.suffix(20))
            case .unknown(let rawFrame, let receivedAt):
                session.auxiliaryFrames.append(.init(receivedAt: receivedAt, rawFrame: rawFrame))
                session.auxiliaryFrames = Array(session.auxiliaryFrames.suffix(40))
            case .reading(let reading):
                session.preview = reading
                if reading.quality == .unknown, reading.spo2 != nil, reading.pulseRate != nil {
                    session.transport.markValidReadingReceived(connectionID: connectionID)
                } else {
                    session.transport.markReadingUnavailable(connectionID: connectionID)
                }
                let waves = session.waveforms
                let auxiliary = session.auxiliaryFrames
                session.waveforms.removeAll()
                session.auxiliaryFrames.removeAll()
                guard let binding = session.association, let directory = session.directory else { continue }
                let origin = engine
                let encounter = encounterIdentity
                let generation = session.generation
                let prior = session.ingestionTask
                let taskID = UUID()
                let task = Task { @MainActor [weak self] in
                    defer { session.ingestionTasks.removeValue(forKey: taskID) }
                    await prior?.value
                    guard let self, !Task.isCancelled,
                          !session.encounterTransitionInProgress, self.engine === origin,
                          session.generation == generation, self.encounterIdentity == encounter else { return }
                    await self.settleCaptureBeforeOperatorEntry()
                    guard !Task.isCancelled, session.generation == generation,
                          !session.encounterTransitionInProgress, self.engine === origin,
                          self.encounterIdentity == encounter,
                          session.transport.connectionID == connectionID else { return }
                    let activeDirectory = await self.encounterStore?.activeDirectoryName()
                    guard activeDirectory == directory, !Task.isCancelled,
                          !session.encounterTransitionInProgress, self.engine === origin,
                          session.generation == generation, self.encounterIdentity == encounter,
                          session.association?.id == binding.id,
                          session.transport.connectionID == connectionID else { return }
                    guard let observation = await origin.recordSensorObservation(reading: reading,
                        waveforms: waves, associationID: binding.id, connectionID: connectionID,
                        encounterID: encounter, auxiliaryFrames: auxiliary) else {
                        if session.generation == generation, self.encounterIdentity == encounter {
                            self.invalidateWirelessSensorAssociation()
                            session.message = "Sensor association ended. Confirm the current casualty before recording again."
                        }
                        return
                    }
                    guard !Task.isCancelled, session.generation == generation,
                          self.encounterIdentity == encounter, self.engine === origin else { return }
                    await self.refreshPatientSnapshot(persist: false, recordVitals: false)
                    guard session.generation == generation, self.encounterIdentity == encounter else { return }
                    self.appendSensorReading(observation)
                    await self.persistNewEvents()
                    guard session.generation == generation, self.encounterIdentity == encounter else { return }
                    await self.persistSectionC()
                }
                session.ingestionTasks[taskID] = task
                session.ingestionTask = task
            }
        }
    }

    /// Sample-only grid column; inherited BP/RR and operator-protected fields
    /// never acquire the sensor's receipt time.
    func appendSensorReading(_ observation: SensorObservationPayload) {
        guard let reading = sensorSectionCReading(observation) else { return }
        guard !vitalsLog.contains(where: { $0.id == reading.id }) else { return }
        // The event log retains every frame. Reserve at most one automatic
        // column so a 1 Hz stream cannot evict all operator observations in
        // four seconds. The column always carries this sample's own time.
        vitalsLog.removeAll { $0.sensorSource != nil }
        vitalsLog.append(reading)
        vitalsLog = Array(vitalsLog.suffix(4))
    }

    private func sensorSectionCReading(_ observation: SensorObservationPayload) -> SectionCReading? {
        guard observation.patientId == "PATIENT_1", observation.hasAppliedVitals else { return nil }
        return SectionCReading(id: observation.reading.id, timestamp: observation.observationTime,
            vitals: observation.appliedVitals, avpu: nil,
            sensorSource: SensorReadingSource(observationID: observation.id,
                timeBasis: observation.timeBasis.rawValue, reviewStatus: observation.reviewStatus.rawValue,
                receivedAt: observation.reading.receivedAt))
    }

    /// The protected event is authoritative if the process stopped between the
    /// observation append and the derived Section C file write.
    func recoverSensorReadings(from log: EncounterLog) {
        let observations = log.events.compactMap { event -> SensorObservationPayload? in
            if case .sensorObservation(let observation) = event,
               observation.patientId == "PATIENT_1", observation.hasAppliedVitals { return observation }
            return nil
        }
        if let observation = observations.last, let reading = sensorSectionCReading(observation) {
            vitalsLog.removeAll { $0.sensorSource != nil }
            vitalsLog.append(reading)
        }
        vitalsLog.sort { $0.timestamp < $1.timestamp }
        vitalsLog = Array(vitalsLog.suffix(4))
    }
}
