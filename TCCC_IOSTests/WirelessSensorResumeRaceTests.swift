import XCTest
import TCCCDomain
import TCCCExtractor
@testable import TCCC_IOS

@MainActor
final class WirelessSensorResumeRaceTests: XCTestCase {
    func testSecondDisconnectBeforeResumePublishesKeepsConsentForAnotherConnection() async throws {
        let (state, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        let intent = try await suspendInitialAssociation(in: state)
        let origin = state.engine
        let encounter = state.encounterIdentity
        let ready = ResumeCompletionGate()
        let release = ResumeCompletionGate()
        var resumed: SensorAssociationPayload?
        var completionWasCanceled = false
        let pending = Task { @MainActor in
            resumed = await origin.resumeSensorAssociation(associationID: intent.id,
                deviceID: intent.deviceID, connectionID: UUID(), encounterID: encounter)
            await ready.open()
            await release.wait()
            completionWasCanceled = Task.isCancelled
            if let resumed {
                await state.handleInterruptedWirelessSensorResume(resumed,
                    intent: intent, origin: origin, encounter: encounter)
            }
        }
        state.wirelessSensors.resumeTask = pending
        state.wirelessSensors.bindingInProgress = true
        await ready.wait()

        // The engine has created B, while the app still holds paused consent A.
        // A second link loss cancels B's pending publication and drains its cleanup.
        let drain = state.invalidateWirelessSensorAssociation(preservingAssociation: true)
        await state.refreshPatientSnapshot(persist: false, recordVitals: false)
        await release.open()
        await drain?.value

        let binding = try XCTUnwrap(resumed)
        XCTAssertTrue(completionWasCanceled)
        XCTAssertNil(state.wirelessSensors.association)
        XCTAssertEqual(state.wirelessSensors.resumableAssociation?.id, binding.id)
        XCTAssertNil(state.wirelessSensors.resumeTask)
        let snapshot = await origin.snapshotWithSensorOrigins()
        XCTAssertNil(snapshot.activeSensorAssociation)
        XCTAssertEqual(snapshot.suspendedSensorAssociation?.id, binding.id)

        let next = await origin.resumeSensorAssociation(associationID: binding.id,
            deviceID: intent.deviceID, connectionID: UUID(), encounterID: encounter)
        XCTAssertNotNil(next, "A second transient loss must not require new operator consent")
        XCTAssertNotEqual(next?.id, binding.id)
    }

    func testExplicitStopBeforeResumePublishesRevokesTheFreshEngineBinding() async throws {
        let (state, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        let intent = try await suspendInitialAssociation(in: state)
        let origin = state.engine
        let encounter = state.encounterIdentity
        let ready = ResumeCompletionGate()
        let release = ResumeCompletionGate()
        var resumed: SensorAssociationPayload?
        var completionWasCanceled = false
        let pending = Task { @MainActor in
            resumed = await origin.resumeSensorAssociation(associationID: intent.id,
                deviceID: intent.deviceID, connectionID: UUID(), encounterID: encounter)
            await ready.open()
            await release.wait()
            completionWasCanceled = Task.isCancelled
            if let resumed {
                await state.handleInterruptedWirelessSensorResume(resumed,
                    intent: intent, origin: origin, encounter: encounter)
            }
        }
        state.wirelessSensors.resumeTask = pending
        await ready.wait()

        let drain = state.invalidateWirelessSensorAssociation()
        await release.open()
        await drain?.value

        let binding = try XCTUnwrap(resumed)
        XCTAssertTrue(completionWasCanceled)
        XCTAssertNil(state.wirelessSensors.association)
        XCTAssertNil(state.wirelessSensors.resumableAssociation)
        let snapshot = await origin.snapshotWithSensorOrigins()
        XCTAssertNil(snapshot.activeSensorAssociation)
        XCTAssertNil(snapshot.suspendedSensorAssociation)
        let retried = await origin.resumeSensorAssociation(associationID: binding.id,
            deviceID: binding.deviceID, connectionID: UUID(), encounterID: encounter)
        XCTAssertNil(retried, "Stopping during an actor return must revoke the new binding too")
        let log = await origin.snapshotLog()
        XCTAssertTrue(log.events.contains { event in
            if case .sensorAssociation(let payload) = event {
                return payload.kind == .revoked
                    && payload.connectionID == binding.connectionID
                    && payload.encounterID == binding.encounterID
            }
            return false
        })
    }

    func testStaleResumeCleanupCannotRevokeANewerExplicitBinding() async throws {
        let (state, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        let intent = try await suspendInitialAssociation(in: state)
        let origin = state.engine
        let encounter = state.encounterIdentity
        let ready = ResumeCompletionGate()
        let release = ResumeCompletionGate()
        var resumed: SensorAssociationPayload?
        let pending = Task { @MainActor in
            resumed = await origin.resumeSensorAssociation(associationID: intent.id,
                deviceID: intent.deviceID, connectionID: UUID(), encounterID: encounter)
            await ready.open()
            await release.wait()
            if let resumed {
                await state.handleInterruptedWirelessSensorResume(resumed,
                    intent: intent, origin: origin, encounter: encounter)
            }
        }
        state.wirelessSensors.resumeTask = pending
        await ready.wait()

        let drain = state.invalidateWirelessSensorAssociation()
        let replacement = await origin.associateSensor(deviceID: "replacement-synthetic-unit",
            deviceName: "Replacement synthetic sensor", connectionID: UUID(), encounterID: encounter)
        state.wirelessSensors.association = replacement
        await release.open()
        await drain?.value

        let oldBinding = try XCTUnwrap(resumed)
        let newBinding = try XCTUnwrap(replacement)
        XCTAssertNotEqual(oldBinding.id, newBinding.id)
        XCTAssertEqual(state.wirelessSensors.association?.id, newBinding.id)
        XCTAssertNil(state.wirelessSensors.resumableAssociation)
        let snapshot = await origin.snapshotWithSensorOrigins()
        XCTAssertEqual(snapshot.activeSensorAssociation?.id, newBinding.id,
            "Cleanup must target its exact association, never the engine's latest binding")
        XCTAssertNil(snapshot.suspendedSensorAssociation)
    }

    func testPatientSwitchWhileResumeIsPendingClearsPausedConsentImmediately() async throws {
        let (state, defaults, suite) = try makeState()
        defer { defaults.removePersistentDomain(forName: suite) }
        _ = try await suspendInitialAssociation(in: state)
        state.wirelessSensors.bindingInProgress = true

        await state.engine.processTranscript("patient two heart rate 90")
        await state.refreshPatientSnapshot(persist: false, recordVitals: false)

        XCTAssertNil(state.wirelessSensors.association)
        XCTAssertNil(state.wirelessSensors.resumableAssociation,
            "A pending resume must not hide the engine's casualty-switch revocation")
        XCTAssertFalse(state.wirelessSensors.bindingInProgress)
        await state.wirelessSensors.revocationTask?.value
    }

    private func makeState() throws -> (AppState, UserDefaults, String) {
        let suite = "test-wireless-resume-race-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let session = WirelessSensorSession(defaults: defaults)
        // Constructing this transport does not start Bluetooth or alter standard defaults.
        return (AppState(wirelessSensors: session), defaults, suite)
    }

    private func suspendInitialAssociation(in state: AppState) async throws -> SensorAssociationPayload {
        let initial = await state.engine.associateSensor(deviceID: "synthetic-unit",
            deviceName: "Synthetic sensor", connectionID: UUID(), encounterID: state.encounterIdentity)
        let binding = try XCTUnwrap(initial)
        state.wirelessSensors.association = binding
        await state.invalidateWirelessSensorAssociation(preservingAssociation: true)?.value
        XCTAssertEqual(state.wirelessSensors.resumableAssociation?.id, binding.id)
        return binding
    }
}

private actor ResumeCompletionGate {
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
