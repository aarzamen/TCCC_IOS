//
//  PulseOximeterBluetooth.swift
//
//  Offline BLE transport for an S5W-family pulse oximeter.
//
//  Scope of this file: discovery, selection, connection lifetime, subscription to the
//  verified Nordic UART TX notification characteristic, and delivery of raw notification
//  bytes to the owning app. This file never decodes, interprets, stores, or transmits
//  anything. It has no networking, no vendor SDK, no telemetry and no persistence beyond
//  a user toggle plus the identity/display name of the chosen sensor.
//
//  Clinical validity is decided elsewhere: raw notifications alone never move the status
//  to `.receiving`. Only `markValidReadingReceived(connectionID:)`, called by the decoder
//  with a matching connection epoch, can do that.
//
//  Identity model: one `CBCentralManager` per connection attempt lifetime. The manager is
//  retired whenever an attempt or session is torn down, and every central callback is
//  filtered by manager identity while every peripheral callback is filtered by the
//  per-attempt delegate proxy and the stored characteristic object. Callbacks belonging to
//  a retired manager are dropped, not reconciled.
//

import CoreBluetooth
import Foundation
import Observation

/// Transport-wide constants. Kept at file scope (not nested) so nothing here depends on
/// actor isolation. `CBUUID` is created on demand because it is a non-`Sendable` class.
private enum BLEConstants {

    /// Product family prefix. Matched case-insensitively against the advertised local
    /// name and the peripheral name. There is no advertised service UUID to filter on.
    static let nameFamilyPrefix = "S5W"

    /// Verified Nordic UART service, only discovered after connecting.
    static var serviceUUID: CBUUID { CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E") }

    /// Verified notification (TX) characteristic. The RX characteristic is never
    /// discovered and never written: this transport is read-only by design.
    static var txCharacteristicUUID: CBUUID { CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") }

    /// Bounded window used to collect family candidates before deciding whether a single
    /// unit can be auto-selected or the user must disambiguate. A unit that first
    /// advertises after the window closes is handled by re-arming the window, not by the
    /// window itself.
    static let discoveryWindow: Duration = .seconds(4)

    /// Foreground-only bound on a connection attempt, covering both the wait for a usable
    /// manager and the pending `connect(_:options:)`, which never times out on its own.
    static let connectTimeout: Duration = .seconds(15)

    /// A valid reading older than this is no longer considered live data.
    static let readingStaleInterval: TimeInterval = 5

    /// An initial retry burst, followed by a quiet cooldown for continued recovery.
    static let retryDelays: [Duration] = [.seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)]
    static let retryCooldown: Duration = .seconds(60)

    /// A subscribed session must last at least this long before its end earns a fresh
    /// fast retry burst. Without it, a unit that subscribes and immediately drops would
    /// repeatedly reset to the shortest delay instead of reaching the cooldown.
    static let stableSessionInterval: TimeInterval = 30

    /// Shown when neither the advertisement nor the peripheral exposes a usable name.
    static let unnamedDevice = "Pulse oximeter"
}

/// Slots for the transport's delayed work. One task per slot at a time.
private enum TransportTask: Hashable {
    case discoveryWindow
    case connectTimeout
    case retry
    case stale
}

/// Owns everything that must still be released if the transport is deallocated: pending
/// task handles and the CoreBluetooth objects themselves. Task handles are cancelled
/// synchronously from anywhere; the radio teardown is bounced to the main queue, which is
/// the queue every manager here is created with.
///
/// The transport holds this strongly; this holds no reference back, so there is no cycle.
private final class TransportResources: @unchecked Sendable {

    private let lock = NSLock()
    private var tasks: [TransportTask: Task<Void, Never>] = [:]
    private var manager: CBCentralManager?
    private var peripheral: CBPeripheral?

    // MARK: Delayed work

    /// Installs `task`, cancelling whatever occupied the slot. Because every replacement
    /// cancels first, a task that reaches its body past the cancellation check is still
    /// the installed one and may clear its own slot.
    func installTask(_ slot: TransportTask, _ task: Task<Void, Never>) {
        lock.lock()
        let previous = tasks.updateValue(task, forKey: slot)
        lock.unlock()
        previous?.cancel()
    }

    func cancelTask(_ slot: TransportTask) {
        lock.lock()
        let task = tasks.removeValue(forKey: slot)
        lock.unlock()
        task?.cancel()
    }

    func finishTask(_ slot: TransportTask) {
        lock.lock()
        tasks.removeValue(forKey: slot)
        lock.unlock()
    }

    func isPending(_ slot: TransportTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tasks[slot] != nil
    }

    // MARK: Radio (main actor in normal operation, main queue from `dispose`)

    var central: CBCentralManager? {
        lock.lock()
        defer { lock.unlock() }
        return manager
    }

    var activePeripheral: CBPeripheral? {
        lock.lock()
        defer { lock.unlock() }
        return peripheral
    }

    func adopt(central: CBCentralManager) {
        lock.lock()
        manager = central
        lock.unlock()
    }

    func adopt(peripheral: CBPeripheral) {
        lock.lock()
        self.peripheral = peripheral
        lock.unlock()
    }

    /// Retires the manager identity along with any peripheral attached to it.
    func releaseRadio() {
        lock.lock()
        let owner = manager
        let target = peripheral
        manager = nil
        peripheral = nil
        lock.unlock()

        Self.detach(target, from: owner)
        guard let owner else { return }
        owner.delegate = nil
        if owner.state == .poweredOn { owner.stopScan() }
    }

    private static func detach(_ peripheral: CBPeripheral?, from manager: CBCentralManager?) {
        guard let peripheral else { return }
        peripheral.delegate = nil
        guard let manager, peripheral.state == .connecting || peripheral.state == .connected else { return }
        manager.cancelPeripheralConnection(peripheral)
    }

    /// Safe to call from `deinit` on any thread.
    func dispose() {
        lock.lock()
        let pending = Array(tasks.values)
        tasks.removeAll()
        lock.unlock()
        for task in pending { task.cancel() }

        DispatchQueue.main.async { self.releaseRadio() }
    }
}

@MainActor
@Observable
final class PulseOximeterBluetooth: NSObject {

    // MARK: - Public types

    /// A discovered or remembered sensor, identified by the per-app CoreBluetooth
    /// identifier. Nested types do not inherit the enclosing actor isolation, so the
    /// synthesized `Equatable` conformance stays nonisolated.
    struct Device: Identifiable, Equatable {
        let id: UUID
        let name: String
    }

    /// Connection *and* data state. `.connectedAwaitingData` and `.receiving` are
    /// deliberately distinct: a subscribed link that is producing bytes is not the same
    /// thing as a link producing readings the decoder considers valid.
    enum Status: Equatable {
        case disabled
        case permissionNeeded
        case permissionDenied
        case bluetoothOff
        case unavailable
        case searching
        case selectionRequired
        case connecting
        case connectedAwaitingData
        case receiving
        case disconnected

        var displayText: String {
            switch self {
            case .disabled: "Sensor connection off"
            case .permissionNeeded: "Bluetooth permission needed"
            case .permissionDenied: "Bluetooth permission denied in Settings"
            case .bluetoothOff: "Bluetooth is off"
            case .unavailable: "Bluetooth unavailable"
            case .searching: "Searching for sensor"
            case .selectionRequired: "Select a sensor"
            case .connecting: "Connecting"
            case .connectedAwaitingData: "Connected, waiting for data"
            case .receiving: "Receiving data"
            case .disconnected: "Not connected"
            }
        }
    }

    // MARK: - Observable state

    private(set) var status: Status = .disabled
    /// Family candidates known in this foreground cycle, plus the connected unit.
    private(set) var devices: [Device] = []
    private(set) var connectedDevice: Device?
    /// Epoch of the currently subscribed session. `nil` means there is no session that
    /// may produce data. Every accepted connection gets a fresh value.
    private(set) var connectionID: UUID?
    private(set) var autoConnectEnabled: Bool

    // MARK: - Callbacks

    /// Raw TX notification: bytes, source device, session epoch, receive timestamp.
    /// Delivered on the main actor. May be invoked reentrantly with respect to this
    /// object's own mutators; the transport touches no state after invoking it.
    @ObservationIgnored var onNotification: (@MainActor (Data, Device, UUID, Date) -> Void)?

    /// Fired after an active session or in-flight attempt has been torn down and
    /// `connectionID` has already been cleared. Downstream state derived from the old
    /// epoch must be discarded here. It may synchronously call `setEnabled` or
    /// `selectDevice`; that newer work wins over the invalidation that fired it.
    @ObservationIgnored var onSessionInvalidated: (@MainActor () -> Void)?

    // MARK: - Transport internals (not observable)

    private enum Keys {
        static let autoConnect = "PulseOximeterBluetooth.autoConnectEnabled"
        static let deviceIdentifier = "PulseOximeterBluetooth.rememberedDeviceIdentifier"
        static let deviceName = "PulseOximeterBluetooth.rememberedDeviceName"
    }

    @ObservationIgnored private nonisolated let resources = TransportResources()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isForeground = true
    /// A manager that has been created but has not reported its state yet. Nothing may be
    /// retrieved, scanned or connected until `.poweredOn` arrives, and no second manager
    /// is created in the meantime.
    @ObservationIgnored private var centralIsInitializing = false

    /// Monotonic work generation. Bumped by every invalidation *and* by every new attempt
    /// or re-enable, so a caller that resumes after running `onSessionInvalidated` can
    /// detect reentrant work and stand down.
    @ObservationIgnored private var generation = 0

    /// Peripherals discovered by the *current* manager. Cleared when that manager is
    /// retired, so a peripheral from a retired manager is never handed to a new one.
    @ObservationIgnored private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var deviceNames: [UUID: String] = [:]

    /// Identity approved for the attempt that is starting or in flight. The peripheral
    /// object itself lives in `resources`.
    @ObservationIgnored private var pendingConnectTarget: UUID?
    @ObservationIgnored private var attemptTarget: UUID?
    @ObservationIgnored private var sessionProxy: PeripheralSessionProxy?

    /// The exact service/characteristic pair verified for this session. Compared by object
    /// identity so a same-UUID characteristic from another service, or a delayed callback
    /// about a previous discovery, cannot be mistaken for the subscription.
    @ObservationIgnored private var subscribedService: CBService?
    @ObservationIgnored private var subscribedCharacteristic: CBCharacteristic?

    @ObservationIgnored private var isScanning = false
    /// Saturates at the initial burst length; later attempts use the cooldown.
    @ObservationIgnored private var retryCount = 0
    /// Set when a direct connect to the remembered identity fails in the foreground.
    /// `retrievePeripherals` happily returns a unit that is nowhere in range, so the next
    /// ladder step looks for it (and for replacements) instead of dialling it blind.
    @ObservationIgnored private var rememberedNeedsRediscovery = false

    @ObservationIgnored private var lastValidReading: Date?
    @ObservationIgnored private var sessionEstablishedAt: Date?

    @ObservationIgnored private var rememberedID: UUID?
    @ObservationIgnored private var rememberedName: String?

    private var central: CBCentralManager? { resources.central }
    private var activePeripheral: CBPeripheral? { resources.activePeripheral }

    // MARK: - Lifecycle

    /// Reads the persisted toggle. No `CBCentralManager` is created here, so an app that
    /// launches with auto-connect saved off never touches the Bluetooth stack and never
    /// triggers the OS privacy prompt.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.autoConnect) == nil {
            self.autoConnectEnabled = true
        } else {
            self.autoConnectEnabled = defaults.bool(forKey: Keys.autoConnect)
        }
        super.init()

        if let raw = defaults.string(forKey: Keys.deviceIdentifier), let id = UUID(uuidString: raw) {
            rememberedID = id
            let savedName = defaults.string(forKey: Keys.deviceName)
            rememberedName = savedName
            if let savedName, !savedName.isEmpty {
                deviceNames[id] = savedName
            }
        }
        status = autoConnectEnabled ? .disconnected : .disabled
    }

    /// Cancels pending delayed work and releases the radio. Weak captures keep the tasks
    /// from retaining the transport, but they would otherwise stay scheduled.
    deinit {
        resources.dispose()
    }

    /// Idempotent. Call once from the app's main-actor lifecycle plumbing.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard autoConnectEnabled else {
            status = .disabled
            return
        }
        activate()
    }

    /// Persists the Settings toggle and applies it immediately.
    ///
    /// Turning it off synchronously invalidates the session epoch, retires the manager,
    /// cancels every timer and drops any pending or connected peripheral before returning.
    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Keys.autoConnect)
        // A repeated Settings assignment must not invalidate the watchdog or discovery
        // window belonging to otherwise unchanged work.
        guard enabled != autoConnectEnabled else { return }
        autoConnectEnabled = enabled
        if enabled {
            // Re-enabling supersedes any invalidation guard that is still unwinding.
            generation &+= 1
            retryCount = 0
            rememberedNeedsRediscovery = false
            resources.cancelTask(.retry)
            guard hasStarted else {
                status = .disconnected
                return
            }
            if status == .disabled { status = .disconnected }
            activate()
        } else {
            shutdown(finalStatus: .disabled, retiringCentral: true)
        }
    }

    /// Explicit, unambiguous user selection. Restricted to units this transport actually
    /// offered — a family candidate from the current scan, or the remembered identity.
    /// Arbitrary identifiers are ignored.
    func selectDevice(_ id: UUID) {
        guard hasStarted, autoConnectEnabled else { return }
        guard devices.contains(where: { $0.id == id }) || id == rememberedID else { return }

        // Prefer the label the user actually tapped over a late peripheral name change.
        let name = deviceNames[id] ?? (id == rememberedID ? rememberedName : nil) ?? BLEConstants.unnamedDevice

        let gen = invalidateSession()
        guard gen == generation, autoConnectEnabled else { return }

        deviceNames[id] = name
        remember(Device(id: id, name: name))
        retryCount = 0
        rememberedNeedsRediscovery = false
        resources.cancelTask(.retry)
        startConnection(to: id)
    }

    /// Foreground entry point. Idempotent: repeated calls never disrupt a live connection,
    /// never restart the candidate-selection window, and never restart the fast retry
    /// burst within the same foreground cycle.
    func applicationDidBecomeActive() {
        let resumingFromBackground = !isForeground
        isForeground = true
        reconcileStaleReading()
        guard hasStarted, autoConnectEnabled else { return }
        if resumingFromBackground {
            // One fresh ladder per foreground cycle.
            retryCount = 0
            rememberedNeedsRediscovery = false
            resources.cancelTask(.retry)
        }
        activate()
    }

    /// Background entry point. Stops the broad scan and the foreground-only timers, because
    /// a name-family scan cannot run in the background (this product advertises no service
    /// UUID). An established connection, a pending system connect and a running backoff are
    /// all left alone: entering the background must not reset the backoff or shortcut a
    /// delay that is already counting down.
    func applicationDidEnterBackground() {
        guard isForeground else { return }
        isForeground = false

        stopScan()
        devices = connectedDevice.map { [$0] } ?? []
        resources.cancelTask(.connectTimeout)
        resources.cancelTask(.stale)

        guard hasStarted, autoConnectEnabled else { return }
        resumeConnectionWorkIfNeeded()
    }

    // MARK: - Decoder feedback

    /// Called by the clinical decoder when a packet it accepts as a valid reading has been
    /// parsed for the given epoch. This is the only path to `.receiving`.
    func markValidReadingReceived(connectionID id: UUID) {
        guard let active = connectionID, active == id else { return }
        lastValidReading = Date()
        if status != .receiving { status = .receiving }
        armStaleCheck()
    }

    /// Called by the decoder when the stream no longer yields a valid reading (probe off,
    /// searching, unparseable frames). Returns the session to "connected, no data".
    func markReadingUnavailable(connectionID id: UUID) {
        guard let active = connectionID, active == id else { return }
        lastValidReading = nil
        resources.cancelTask(.stale)
        if status != .connectedAwaitingData { status = .connectedAwaitingData }
    }

    // MARK: - Activation

    private func activate() {
        ensureCentral()
        evaluateCentralState()
    }

    /// Creates the manager for the next attempt. Nothing is retrieved, scanned or connected
    /// until its `.poweredOn` state arrives.
    private func ensureCentral() {
        guard autoConnectEnabled, hasStarted, central == nil, !centralIsInitializing else { return }
        centralIsInitializing = true
        // Main-queue delivery keeps every delegate callback on the main actor, which is
        // what the @preconcurrency conformances below assert at runtime.
        resources.adopt(central: CBCentralManager(
            delegate: self,
            queue: .main,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        ))
    }

    /// Retires the current manager identity. Late callbacks from it are dropped by the
    /// identity guards rather than reconciled, so no cancellation ledger is needed.
    private func retireCentral() {
        resources.cancelTask(.discoveryWindow)
        resources.releaseRadio()
        isScanning = false
        centralIsInitializing = false
        sessionProxy = nil
        subscribedService = nil
        subscribedCharacteristic = nil
        // These objects belong to the retired manager.
        discoveredPeripherals.removeAll()
    }

    private func isCurrentCentral(_ manager: CBCentralManager) -> Bool {
        central === manager
    }

    /// Maps radio + authorization state onto `status` and resumes work when usable.
    /// The OS privacy prompt is the only prompt this transport ever causes; it presents
    /// no dialogs of its own.
    private func evaluateCentralState() {
        guard autoConnectEnabled, let central else { return }

        switch CBManager.authorization {
        case .denied, .restricted:
            shutdown(finalStatus: .permissionDenied)
            return
        case .notDetermined:
            if central.state != .poweredOn {
                // The prompt is in flight; do not tear anything down.
                status = .permissionNeeded
                return
            }
        default:
            break
        }

        switch central.state {
        case .poweredOn:
            if status == .disabled || status == .bluetoothOff || status == .unavailable
                || status == .permissionNeeded || status == .permissionDenied {
                status = .disconnected
            }
            resumeConnectionWorkIfNeeded()
        case .poweredOff:
            shutdown(finalStatus: .bluetoothOff)
        case .unauthorized:
            shutdown(finalStatus: .permissionDenied)
        case .unsupported:
            shutdown(finalStatus: .unavailable)
        case .resetting:
            shutdown(finalStatus: .unavailable)
        case .unknown:
            // Transient state before the first real update (including right after the
            // manager is created). Wait for the callback instead of flashing an error.
            break
        @unknown default:
            shutdown(finalStatus: .unavailable)
        }
    }

    /// Idempotent: no-ops while a session is live, an attempt is in flight, a scan is
    /// running, or a backoff or cooldown is counting down.
    private func resumeConnectionWorkIfNeeded() {
        guard autoConnectEnabled, hasStarted else { return }

        reconcileStaleReading()

        if connectionID != nil {
            armStaleCheck()
            return
        }
        if activePeripheral != nil {
            armConnectTimeout()
            return
        }
        if pendingConnectTarget != nil {
            armConnectTimeout()
            startPendingConnectIfPossible()
            return
        }
        guard let central, central.state == .poweredOn else {
            ensureCentral()
            return
        }
        guard !resources.isPending(.retry), !isScanning else { return }

        beginConnectionAttemptOrDiscovery()
    }

    private func beginConnectionAttemptOrDiscovery() {
        guard autoConnectEnabled, hasStarted, connectionID == nil,
              activePeripheral == nil, pendingConnectTarget == nil,
              let central, central.state == .poweredOn else { return }

        if let rememberedID, !(isForeground && rememberedNeedsRediscovery) {
            startConnection(to: rememberedID)
            return
        }

        // A name-family scan is foreground-only; in the background the direct connect above
        // is the only legal reconnection.
        guard isForeground else { return }
        startDiscovery()
    }

    // MARK: - Discovery

    private func startDiscovery() {
        guard !isScanning, isForeground, autoConnectEnabled,
              connectionID == nil, activePeripheral == nil, pendingConnectTarget == nil,
              let central, central.state == .poweredOn else { return }

        discoveredPeripherals = discoveredPeripherals.filter { $0.key == rememberedID }
        devices = []
        isScanning = true
        status = .searching
        // No advertised service UUID exists for this product, so the filter must be nil
        // and the family is identified by name prefix below.
        central.scanForPeripherals(withServices: nil, options: nil)
        armDiscoveryWindow()
    }

    private func armDiscoveryWindow() {
        let gen = generation
        resources.installTask(.discoveryWindow, Task { [weak self] in
            try? await Task.sleep(for: BLEConstants.discoveryWindow)
            guard !Task.isCancelled, let self else { return }
            self.resources.finishTask(.discoveryWindow)
            self.resolveDiscoveryWindow(generation: gen)
        })
    }

    /// Decides only after the whole window has elapsed, so the first unit to answer does not
    /// win over a sibling that answers a moment later. Units that only start advertising
    /// after the window are picked up by the re-armed window in `handleDiscovery`.
    private func resolveDiscoveryWindow(generation gen: Int) {
        guard gen == generation, isScanning, autoConnectEnabled,
              connectionID == nil, activePeripheral == nil, pendingConnectTarget == nil else { return }

        if rememberedID != nil {
            // The remembered unit did not advertise inside this window. Never silently
            // switch to a different unit: offer the candidates that did show up and leave
            // the stored identity alone until the user picks one.
            status = devices.isEmpty ? .searching : .selectionRequired
            return
        }

        switch devices.count {
        case 0:
            status = .searching
        case 1:
            let device = devices[0]
            guard discoveredPeripherals[device.id] != nil else {
                status = .searching
                return
            }
            startConnection(to: device.id)
        default:
            status = .selectionRequired
        }
    }

    private func handleDiscovery(peripheral: CBPeripheral, advertisementData: [String: Any]) {
        guard isScanning, autoConnectEnabled else { return }

        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let isRemembered = peripheral.identifier == rememberedID
        // Family name or the remembered identity only: an unrelated Nordic UART peripheral
        // is never listed and never auto-selected.
        guard isRemembered || isFamilyName(advertisedName) || isFamilyName(peripheral.name) else { return }

        discoveredPeripherals[peripheral.identifier] = peripheral
        let name = resolvedName(advertised: advertisedName, peripheral: peripheral)
        deviceNames[peripheral.identifier] = name
        upsert(Device(id: peripheral.identifier, name: name))

        if isRemembered {
            // The preferred unit is genuinely in range: it wins over any replacement.
            rememberedNeedsRediscovery = false
            startConnection(to: peripheral.identifier)
            return
        }

        if !resources.isPending(.discoveryWindow), status != .selectionRequired {
            // The previous window closed with nothing to decide on. Collect siblings of
            // this late arrival before deciding, instead of grabbing the first responder.
            armDiscoveryWindow()
        }
    }

    private func stopScan() {
        resources.cancelTask(.discoveryWindow)
        guard isScanning else { return }
        isScanning = false
        if let central, central.state == .poweredOn { central.stopScan() }
    }

    // MARK: - Connection

    /// Begins a bounded attempt against an approved identity. Callers must have invalidated
    /// any previous session first; the attempt itself starts once a `.poweredOn` manager is
    /// available, which may be the next runloop turn after a retirement.
    private func startConnection(to id: UUID) {
        guard autoConnectEnabled, hasStarted,
              connectionID == nil, activePeripheral == nil else { return }

        // A new attempt supersedes any invalidation guard that is still unwinding.
        generation &+= 1
        stopScan()
        resources.cancelTask(.retry)

        attemptTarget = id
        pendingConnectTarget = id
        status = .connecting
        armConnectTimeout()
        startPendingConnectIfPossible()
    }

    private func startPendingConnectIfPossible() {
        guard let target = pendingConnectTarget, autoConnectEnabled,
              connectionID == nil, activePeripheral == nil else { return }
        guard let manager = central, manager.state == .poweredOn else {
            // Wait for `.poweredOn`; `centralManagerDidUpdateState` comes back through
            // `resumeConnectionWorkIfNeeded`.
            ensureCentral()
            return
        }
        // Only peripherals belonging to this manager are ever used: the cache is emptied
        // whenever a manager is retired.
        guard let peripheral = discoveredPeripherals[target]
                ?? manager.retrievePeripherals(withIdentifiers: [target]).first else {
            pendingConnectTarget = nil
            failCurrentAttempt()
            return
        }

        pendingConnectTarget = nil
        discoveredPeripherals[target] = peripheral
        if deviceNames[target] == nil {
            deviceNames[target] = resolvedName(advertised: nil, peripheral: peripheral)
        }

        let proxy = PeripheralSessionProxy(owner: self)
        sessionProxy = proxy
        peripheral.delegate = proxy
        resources.adopt(peripheral: peripheral)

        status = .connecting
        manager.connect(peripheral, options: nil)
        armConnectTimeout()
    }

    /// Foreground-only watchdog covering both the wait for a usable manager and the pending
    /// connect. In the background a pending connect is legitimate and long-lived, and no
    /// timer is guaranteed to run anyway.
    private func armConnectTimeout() {
        guard isForeground, connectionID == nil,
              activePeripheral != nil || pendingConnectTarget != nil else {
            resources.cancelTask(.connectTimeout)
            return
        }
        // One window per attempt: re-entering the foreground repeatedly must not keep
        // pushing the deadline out.
        guard !resources.isPending(.connectTimeout) else { return }
        let gen = generation
        resources.installTask(.connectTimeout, Task { [weak self] in
            try? await Task.sleep(for: BLEConstants.connectTimeout)
            guard !Task.isCancelled, let self else { return }
            self.resources.finishTask(.connectTimeout)
            self.handleConnectTimeout(generation: gen)
        })
    }

    private func handleConnectTimeout(generation gen: Int) {
        guard gen == generation, connectionID == nil,
              activePeripheral != nil || pendingConnectTarget != nil else { return }
        failCurrentAttempt()
    }

    /// Tears the attempt down and schedules recovery with a bounded retry rate.
    private func failCurrentAttempt() {
        let target = attemptTarget ?? pendingConnectTarget
        // A link that was established and later dropped says nothing about reachability;
        // only an attempt that never got there suggests the stored identity is not here.
        let neverEstablished = connectionID == nil
        let gen = invalidateSession()
        guard gen == generation else { return }

        if isForeground, neverEstablished, let target, target == rememberedID {
            rememberedNeedsRediscovery = true
        }
        if status != .bluetoothOff, status != .permissionDenied,
           status != .unavailable, status != .disabled {
            status = .disconnected
        }
        scheduleRetry()
    }

    /// Uses 2/4/8/16/30 seconds, then 60 seconds between subsequent attempts while enabled.
    /// Backgrounding does not shorten the delay. A suspended process has no guaranteed
    /// wake-up, so recovery resumes when the app is allowed to run again.
    private func scheduleRetry() {
        guard hasStarted, autoConnectEnabled, !resources.isPending(.retry),
              connectionID == nil, activePeripheral == nil, pendingConnectTarget == nil else { return }

        let delay = retryCount < BLEConstants.retryDelays.count
            ? BLEConstants.retryDelays[retryCount]
            : BLEConstants.retryCooldown
        retryCount = min(retryCount + 1, BLEConstants.retryDelays.count)
        let gen = generation
        resources.installTask(.retry, Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.resources.finishTask(.retry)
            self.handleRetryFired(generation: gen)
        })
    }

    private func handleRetryFired(generation gen: Int) {
        guard gen == generation, autoConnectEnabled,
              connectionID == nil, activePeripheral == nil, pendingConnectTarget == nil else { return }
        resumeConnectionWorkIfNeeded()
    }

    // MARK: - Session teardown

    /// Invalidates the current epoch and any in-flight attempt, then notifies the owner.
    /// Returns the generation this invalidation minted — *not* whatever the counter holds
    /// afterwards — so a caller comparing it against `generation` detects any newer work
    /// started reentrantly from `onSessionInvalidated` and stands down.
    ///
    /// `retiringCentral` forces the manager to be dropped even when no peripheral was
    /// attached, and does so *before* the callback runs, so a reentrant re-enable builds on
    /// its own manager instead of one this call is about to destroy.
    @discardableResult
    private func invalidateSession(retiringCentral: Bool = false) -> Int {
        generation &+= 1
        let invalidated = generation

        resources.cancelTask(.connectTimeout)
        resources.cancelTask(.stale)

        let hadAttachment = activePeripheral != nil
        let hadSession = connectionID != nil || hadAttachment || pendingConnectTarget != nil
        let earnedFreshBudget = sessionEstablishedAt.map {
            Date().timeIntervalSince($0) >= BLEConstants.stableSessionInterval
        } ?? false

        connectionID = nil
        connectedDevice = nil
        lastValidReading = nil
        sessionEstablishedAt = nil
        pendingConnectTarget = nil
        attemptTarget = nil

        if hadAttachment || retiringCentral {
            // This manager issued a connect for that peripheral. Retire the whole manager
            // instead of trying to tell its remaining callbacks apart from a new attempt's,
            // and bring up a fresh one for the next attempt (a no-op while disabled).
            retireCentral()
            ensureCentral()
        } else {
            sessionProxy = nil
            subscribedService = nil
            subscribedCharacteristic = nil
        }

        // Only a stable session restarts the fast retry burst after a later disconnect.
        if earnedFreshBudget {
            retryCount = 0
        }

        // Fired last, with all state already cleared, so a reentrant setEnabled/selectDevice
        // from the callback sees a clean object and cannot recurse into this method again.
        if hadSession { onSessionInvalidated?() }
        return invalidated
    }

    /// Full stop: scan, timers, connection and candidate list. The manager is retired only
    /// when the user turns the feature off; radio-state stops keep it so the transport can
    /// still observe Bluetooth coming back.
    private func shutdown(finalStatus: Status, retiringCentral: Bool = false) {
        stopScan()
        resources.cancelTask(.retry)
        retryCount = 0

        let gen = invalidateSession(retiringCentral: retiringCentral)
        guard gen == generation else { return }

        devices = []
        discoveredPeripherals.removeAll()
        status = finalStatus
    }

    // MARK: - Central delegate handling

    private func handleConnected(peripheral: CBPeripheral) {
        guard let active = activePeripheral, active === peripheral else {
            // Not part of the current attempt: do not leave the radio holding a link
            // nothing will ever read from.
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        // Only the verified service, and only its TX characteristic, are ever discovered.
        peripheral.discoverServices([BLEConstants.serviceUUID])
    }

    private func handleConnectionEnded(peripheral: CBPeripheral) {
        guard let active = activePeripheral, active === peripheral else { return }
        failCurrentAttempt()
    }

    // MARK: - Peripheral delegate handling (per-attempt proxy identity)

    fileprivate func handleServicesDiscovered(
        proxy: PeripheralSessionProxy,
        peripheral: CBPeripheral,
        error: Error?
    ) {
        guard isCurrentSession(proxy: proxy, peripheral: peripheral) else { return }
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == BLEConstants.serviceUUID }) else {
            failCurrentAttempt()
            return
        }
        peripheral.discoverCharacteristics([BLEConstants.txCharacteristicUUID], for: service)
    }

    fileprivate func handleCharacteristicsDiscovered(
        proxy: PeripheralSessionProxy,
        peripheral: CBPeripheral,
        service: CBService,
        error: Error?
    ) {
        guard isCurrentSession(proxy: proxy, peripheral: peripheral) else { return }
        // The verified pair: this peripheral's NUS service, and a characteristic that both
        // belongs to that service object and actually advertises notify. Indication-only is
        // not a supported fallback for this product.
        guard error == nil,
              service.uuid == BLEConstants.serviceUUID,
              service.peripheral === peripheral,
              let tx = service.characteristics?.first(where: {
                  $0.uuid == BLEConstants.txCharacteristicUUID
                      && $0.service === service
                      && $0.properties.contains(.notify)
              }) else {
            failCurrentAttempt()
            return
        }

        subscribedService = service
        subscribedCharacteristic = tx
        // Subscription is the only write-like operation performed. The RX characteristic
        // is never discovered and never written.
        peripheral.setNotifyValue(true, for: tx)
    }

    fileprivate func handleNotificationStateChanged(
        proxy: PeripheralSessionProxy,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard isCurrentSession(proxy: proxy, peripheral: peripheral),
              isSubscribedCharacteristic(characteristic) else { return }
        guard error == nil, characteristic.isNotifying else {
            failCurrentAttempt()
            return
        }
        guard connectionID == nil else { return }
        activateSession(peripheral: peripheral)
    }

    fileprivate func handleValueUpdated(
        proxy: PeripheralSessionProxy,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        error: Error?
    ) {
        let receivedAt = Date()
        guard isCurrentSession(proxy: proxy, peripheral: peripheral),
              isSubscribedCharacteristic(characteristic),
              error == nil,
              let data = characteristic.value, !data.isEmpty,
              let epoch = connectionID, let device = connectedDevice else { return }

        // Background timers are not guaranteed, so liveness is re-derived on every packet.
        reconcileStaleReading()
        guard connectionID == epoch else { return }

        // Raw bytes never imply a valid reading: status stays as-is until the decoder
        // calls markValidReadingReceived(connectionID:). The callback may reentrantly
        // disable or switch the transport, so no state is touched after this call.
        onNotification?(data, device, epoch, receivedAt)
    }

    /// The attempt's own proxy object and the attempt's own peripheral object. A proxy from
    /// an earlier attempt is already unreferenced, and a peripheral that is not the current
    /// one cannot match by identity.
    private func isCurrentSession(proxy: PeripheralSessionProxy, peripheral: CBPeripheral) -> Bool {
        guard autoConnectEnabled, proxy === sessionProxy,
              let active = activePeripheral, active === peripheral else { return false }
        return true
    }

    /// Object identity against the stored pair, plus the UUIDs that were verified when it
    /// was stored. UUID equality alone would also accept a same-UUID characteristic from
    /// another service.
    private func isSubscribedCharacteristic(_ characteristic: CBCharacteristic) -> Bool {
        guard let expected = subscribedCharacteristic, characteristic === expected,
              let service = subscribedService, characteristic.service === service,
              service.uuid == BLEConstants.serviceUUID,
              expected.uuid == BLEConstants.txCharacteristicUUID else { return false }
        return true
    }

    /// A successful subscription mints the epoch and remembers the unit. Only a session
    /// lasting at least `stableSessionInterval` restarts the fast retry burst when it ends;
    /// a unit that repeatedly subscribes and drops settles into the cooldown.
    private func activateSession(peripheral: CBPeripheral) {
        resources.cancelTask(.connectTimeout)
        resources.cancelTask(.retry)
        rememberedNeedsRediscovery = false

        let name = deviceNames[peripheral.identifier] ?? resolvedName(advertised: nil, peripheral: peripheral)
        deviceNames[peripheral.identifier] = name
        let device = Device(id: peripheral.identifier, name: name)

        remember(device)
        upsert(device)
        connectedDevice = device
        connectionID = UUID()
        sessionEstablishedAt = Date()
        lastValidReading = nil
        status = .connectedAwaitingData
    }

    // MARK: - Reading liveness

    private func armStaleCheck() {
        resources.cancelTask(.stale)
        guard isForeground, connectionID != nil, let last = lastValidReading else { return }
        let remaining = max(BLEConstants.readingStaleInterval - Date().timeIntervalSince(last), 0.1)
        let gen = generation
        resources.installTask(.stale, Task { [weak self] in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled, let self else { return }
            self.resources.finishTask(.stale)
            guard gen == self.generation else { return }
            self.reconcileStaleReading()
        })
    }

    /// Demotes `.receiving` once the last valid reading is older than the stale interval.
    /// Called from the timer, on foreground and on every notification, because a suspended
    /// app's timers may simply not run.
    private func reconcileStaleReading() {
        guard connectionID != nil, let last = lastValidReading else { return }
        guard Date().timeIntervalSince(last) > BLEConstants.readingStaleInterval else { return }
        lastValidReading = nil
        if status == .receiving { status = .connectedAwaitingData }
    }

    // MARK: - Naming and persistence

    private func isFamilyName(_ name: String?) -> Bool {
        guard let name else { return false }
        return name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix(BLEConstants.nameFamilyPrefix.lowercased())
    }

    private func resolvedName(advertised: String?, peripheral: CBPeripheral) -> String {
        let candidates: [String?] = [
            advertised,
            peripheral.name,
            deviceNames[peripheral.identifier],
            peripheral.identifier == rememberedID ? rememberedName : nil
        ]
        for candidate in candidates {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return BLEConstants.unnamedDevice
    }

    private func upsert(_ device: Device) {
        if let index = devices.firstIndex(where: { $0.id == device.id }) {
            if devices[index] != device { devices[index] = device }
        } else {
            devices.append(device)
        }
        devices.sort { lhs, rhs in
            lhs.name == rhs.name
                ? lhs.id.uuidString < rhs.id.uuidString
                : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Persists only the selection identity and its display name. Nothing else about the
    /// sensor, and nothing about what it measured, ever leaves memory.
    private func remember(_ device: Device) {
        rememberedID = device.id
        rememberedName = device.name
        defaults.set(device.id.uuidString, forKey: Keys.deviceIdentifier)
        defaults.set(device.name, forKey: Keys.deviceName)
    }
}

// MARK: - CBCentralManagerDelegate

// CoreBluetooth was created with `queue: .main`, so every callback below really does run
// on the main actor; @preconcurrency turns that into a checked runtime assertion instead
// of an unchecked assumption. Every callback is filtered by manager identity: a retired
// manager is never adopted back, and its callbacks are ignored.
extension PulseOximeterBluetooth: @preconcurrency CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard isCurrentCentral(central) else { return }
        centralIsInitializing = false
        evaluateCentralState()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isCurrentCentral(central) else { return }
        handleDiscovery(peripheral: peripheral, advertisementData: advertisementData)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard isCurrentCentral(central) else { return }
        handleConnected(peripheral: peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard isCurrentCentral(central) else { return }
        handleConnectionEnded(peripheral: peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        guard isCurrentCentral(central) else { return }
        handleConnectionEnded(peripheral: peripheral)
    }
}

// MARK: - Peripheral delegate proxy

/// One proxy per connection attempt. Callbacks carry the proxy itself, so the transport
/// compares object identity rather than a value that a later attempt could reproduce.
///
/// Ownership: the transport holds the proxy strongly, the peripheral holds it weakly, and
/// the proxy holds the transport weakly. Dropping `sessionProxy` therefore also drops the
/// peripheral's delegate, which is what bounds late peripheral callbacks; the identity
/// guards cover whatever is already queued.
@MainActor
private final class PeripheralSessionProxy: NSObject, @preconcurrency CBPeripheralDelegate {

    private weak var owner: PulseOximeterBluetooth?

    init(owner: PulseOximeterBluetooth) {
        super.init()
        self.owner = owner
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        owner?.handleServicesDiscovered(proxy: self, peripheral: peripheral, error: error)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        owner?.handleCharacteristicsDiscovered(
            proxy: self,
            peripheral: peripheral,
            service: service,
            error: error
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        owner?.handleNotificationStateChanged(
            proxy: self,
            peripheral: peripheral,
            characteristic: characteristic,
            error: error
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        owner?.handleValueUpdated(
            proxy: self,
            peripheral: peripheral,
            characteristic: characteristic,
            error: error
        )
    }
}
