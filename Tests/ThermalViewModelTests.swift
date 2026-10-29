import XCTest
@testable import ThermalControl

@MainActor
final class ThermalViewModelTests: XCTestCase {
    func testRefreshCoalescesConcurrentRequests() async {
        let client = ThermalViewModelClient()
        client.suspendCapabilities = true
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())

        viewModel.refresh()
        await waitUntil { client.capabilityCalls == 1 }
        viewModel.refresh()
        viewModel.refresh()

        XCTAssertTrue(viewModel.hasPendingRefreshForTesting)
        client.resumeCapabilities(nil)
        await waitUntil { client.capabilityCalls == 2 }

        XCTAssertEqual(client.capabilityCalls, 2)
    }

    func testStaleRefreshDoesNotApplyAfterSleep() async {
        let client = ThermalViewModelClient()
        client.suspendCapabilities = true
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())

        viewModel.refresh()
        await waitUntil { client.capabilityCalls == 1 }
        viewModel.prepareForSleepForTesting()
        client.resumeCapabilities(client.capabilities)
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertTrue(viewModel.isSleepingForTesting)
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        XCTAssertFalse(viewModel.fan.fanControl)
        XCTAssertFalse(viewModel.isRefreshInFlightForTesting)
    }

    func testSleepCancelsPendingRefresh() async {
        let client = ThermalViewModelClient()
        client.suspendCapabilities = true
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())

        viewModel.refresh()
        await waitUntil { viewModel.isRefreshInFlightForTesting }
        viewModel.refresh()
        XCTAssertTrue(viewModel.hasPendingRefreshForTesting)

        viewModel.prepareForSleepForTesting()

        XCTAssertFalse(viewModel.isRefreshInFlightForTesting)
        XCTAssertFalse(viewModel.hasPendingRefreshForTesting)
        XCTAssertEqual(viewModel.connectionState, .disconnected)
        client.resumeCapabilities(nil)
    }

    func testReconnectKeepsLatestGeneration() {
        let client = ThermalViewModelClient()
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())

        viewModel.reconnect()
        let firstGeneration = viewModel.reconnectGenerationForTesting
        viewModel.reconnect()

        XCTAssertEqual(viewModel.reconnectGenerationForTesting, firstGeneration + 1)
        XCTAssertEqual(client.connectCalls, 2)
        XCTAssertEqual(viewModel.connectionState, .connecting)
    }

    func testHeartbeatCoalescesConcurrentPings() async {
        let client = ThermalViewModelClient()
        client.suspendPing = true
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())

        viewModel.beat()
        viewModel.beat()
        await waitUntil { client.pingCalls == 1 }

        XCTAssertTrue(viewModel.isHeartbeatInFlightForTesting)
        client.resumePing(true)
        await waitUntil { !viewModel.isHeartbeatInFlightForTesting }
        XCTAssertEqual(client.pingCalls, 1)
    }

    func testCanceledLocalSensorSnapshotDoesNotMutateState() async {
        let client = ThermalViewModelClient()
        let loader = SuspendedLocalSensorLoader()
        let viewModel = ThermalViewModel(
            xpc: client,
            alerts: AlertPresenter(),
            loadLocalSensors: { includeFallback in loader.load(includeFallback: includeFallback) }
        )

        viewModel.scheduleLocalSensorsForTesting(includeFallback: true)
        await waitUntil { loader.isWaiting }
        viewModel.prepareForSleepForTesting()
        loader.resume(snapshot: LocalSensorSnapshot(
            power: SensorReader.PowerInfo(present: true, percent: 88),
            fans: [FanChannel(
                index: 0,
                actualRPM: 2_500,
                targetRPM: 2_500,
                minRPM: 1_000,
                maxRPM: 6_000,
                modeRaw: FanMode.system.rawValue,
                modeKey: "F0Md"
            )],
            temperatures: [TempReading(key: SMCKey.tc0P.rawValue, celsius: 70)]
        ))
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertFalse(viewModel.isLocalSensorReadInFlightForTesting)
        XCTAssertFalse(viewModel.battery.batteryPresent)
        XCTAssertTrue(viewModel.fan.fans.isEmpty)
        XCTAssertTrue(viewModel.temps.isEmpty)
    }

    func testMissingRequiredTelemetryNeverEnablesControls() async {
        let client = ThermalViewModelClient()
        client.missingTelemetry = true
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())
        viewModel.connectionState = .connected
        viewModel.refresh()
        await waitUntil { !viewModel.isRefreshInFlightForTesting }
        XCTAssertFalse(viewModel.controlsEnabled)
        XCTAssertFalse(viewModel.battery.hasConfirmedChargeState)
    }

    func testProtocolMismatchNeverEnablesControls() async {
        let client = ThermalViewModelClient()
        client.capabilities.protocolVersion = TC.protocolVersion + 1
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())
        viewModel.refresh()
        await waitUntil { !viewModel.isRefreshInFlightForTesting }
        XCTAssertFalse(viewModel.controlsEnabled)
        XCTAssertEqual(viewModel.connectionState, .error)
    }

    func testEmptyTemperatureSnapshotClearsOldReadings() async {
        let client = ThermalViewModelClient()
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())
        viewModel.temps = [TempReading(key: "TC0P", celsius: 70)]
        viewModel.refresh()
        await waitUntil { !viewModel.isRefreshInFlightForTesting }
        XCTAssertTrue(viewModel.temps.isEmpty)
        XCTAssertTrue(viewModel.temperaturesUnavailable)
    }

    func testSuccessfulRefreshDoesNotClearCommandError() async {
        let client = ThermalViewModelClient()
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())
        viewModel.noteError("fan write failed")

        viewModel.refresh()
        await waitUntil { !viewModel.isRefreshInFlightForTesting }

        XCTAssertEqual(viewModel.lastError, "fan write failed")
    }

    func testRestoreCompletionCannotReconnectSleepingSession() async {
        let client = ThermalViewModelClient()
        client.suspendRestore = true
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())
        viewModel.connectionState = .connected
        viewModel.restoreSystem()
        await waitUntil { client.pendingRestore != nil }

        viewModel.prepareForSleepForTesting()
        client.pendingRestore?.resume(returning: (true, nil))
        client.pendingRestore = nil
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(viewModel.connectionState, .disconnected)
    }

    func testQuitRestoresOnlyTransientOverrides() async {
        let client = ThermalViewModelClient()
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())
        viewModel.connectionState = .connected
        let ready = await viewModel.prepareToQuit()
        XCTAssertTrue(ready)
        XCTAssertEqual(client.restoredComponents, [RestoreResult.transient])
        XCTAssertTrue(viewModel.isSleepingForTesting)
    }

    func testQuitBlocksNewCommandsWhileRestoreIsPending() async {
        let client = ThermalViewModelClient()
        client.suspendRestore = true
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())
        viewModel.connectionState = .connected
        let quitting = Task { await viewModel.prepareToQuit() }
        await waitUntil { client.pendingRestore != nil }
        XCTAssertTrue(viewModel.isQuitting)
        XCTAssertFalse(viewModel.controlsEnabled)
        XCTAssertFalse(viewModel.isConnected)
        client.pendingRestore?.resume(returning: (false, "Unknown state"))
        client.pendingRestore = nil
        let ready = await quitting.value
        XCTAssertFalse(ready)
        XCTAssertTrue(viewModel.controlsEnabled)
    }

    func testQuitFailureKeepsSessionOpen() async {
        let client = ThermalViewModelClient()
        client.restoreResult = RestoreResult(attempted: RestoreResult.transient, fanError: "Fan unknown")
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())
        viewModel.connectionState = .connected
        let ready = await viewModel.prepareToQuit()
        XCTAssertFalse(ready)
        XCTAssertFalse(viewModel.isSleepingForTesting)
        XCTAssertEqual(viewModel.lastError, "Fan unknown")
    }

    func testRetryRestoresOnlyFailedComponent() async {
        let client = ThermalViewModelClient()
        client.restoreResult = RestoreResult(attempted: RestoreResult.all, fanError: "Fan failed")
        let viewModel = ThermalViewModel(xpc: client, alerts: AlertPresenter())
        viewModel.connectionState = .connected
        viewModel.restoreSystem()
        await waitUntil { viewModel.failedRestoreComponents == RestoreResult.fan }
        client.restoreResult = RestoreResult(attempted: RestoreResult.fan)
        viewModel.retryFailedRestore()
        await waitUntil { client.restoredComponents.count == 2 }
        XCTAssertEqual(client.restoredComponents, [RestoreResult.all, RestoreResult.fan])
    }

    func testOpenSettingsSelectsSettingsTab() {
        let viewModel = ThermalViewModel(xpc: ThermalViewModelClient(), alerts: AlertPresenter())
        viewModel.openSettings()
        XCTAssertEqual(viewModel.selectedDashboardTab, .settings)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for lifecycle state")
    }
}

private final class SuspendedLocalSensorLoader: @unchecked Sendable {
    private let condition = NSCondition()
    private var waiting = false
    private var snapshot: LocalSensorSnapshot?

    var isWaiting: Bool {
        condition.lock()
        defer { condition.unlock() }
        return waiting
    }

    func load(includeFallback: Bool) -> LocalSensorSnapshot {
        condition.lock()
        waiting = true
        condition.broadcast()
        while snapshot == nil { condition.wait() }
        guard let result = snapshot else {
            condition.unlock()
            fatalError("Local sensor loader resumed without a snapshot")
        }
        condition.unlock()
        return result
    }

    func resume(snapshot: LocalSensorSnapshot) {
        condition.lock()
        self.snapshot = snapshot
        condition.broadcast()
        condition.unlock()
    }
}

@MainActor
private final class ThermalViewModelClient: ThermalOrchestrationClient {
    var onConnectionLost: (() -> Void)?
    var connectCalls = 0
    var pingCalls = 0
    var capabilityCalls = 0
    var suspendPing = false
    var suspendCapabilities = false
    private var pendingPing: CheckedContinuation<Bool, Never>?
    private var pendingCapabilities: CheckedContinuation<Capabilities?, Never>?

    let capabilities = Capabilities(
        fanCount: 1,
        fanControl: true,
        ftstPresent: false,
        batteryPresent: true,
        batteryControl: true,
        batteryFamily: BatteryFamily.tahoe.rawValue,
        helperVersion: TC.helperVersion
    )

    func connect() { connectCalls += 1 }
    func invalidate() {}

    func ping() async -> Bool {
        pingCalls += 1
        if suspendPing {
            return await withCheckedContinuation { pendingPing = $0 }
        }
        return true
    }

    func resumePing(_ value: Bool) {
        pendingPing?.resume(returning: value)
        pendingPing = nil
        suspendPing = false
    }

    func capabilities() async -> Capabilities? {
        capabilityCalls += 1
        if suspendCapabilities {
            return await withCheckedContinuation { pendingCapabilities = $0 }
        }
        return capabilities
    }

    func resumeCapabilities(_ value: Capabilities?) {
        pendingCapabilities?.resume(returning: value)
        pendingCapabilities = nil
        suspendCapabilities = false
    }

    var missingTelemetry = false
    func fanStatus() async -> FanStatus? {
        missingTelemetry ? nil : FanStatus(fans: [], desiredMode: FanMode.system.rawValue, ftstPresent: false)
    }
    func batteryStatus() async -> BatteryStatus? {
        missingTelemetry ? nil : BatteryStatus(
            present: true, percent: 50, externalAC: true, amperageMA: 0, voltageMV: 12_000,
            upperLimit: 80, lowerLimit: 70, chargingEnabled: true, maintainActive: true,
            forceDischarge: false, keyFamily: "tahoe", canControlCharge: true, dischargeStopVerified: true
        )
    }
    func temps() async -> [TempReading] { [] }
    var suspendRestore = false
    var pendingRestore: CheckedContinuation<(Bool, String?), Never>?
    func restore() async -> (Bool, String?) {
        if suspendRestore {
            return await withCheckedContinuation { pendingRestore = $0 }
        }
        return (true, nil)
    }
    var restoredComponents: [Int] = []
    var restoreResult = RestoreResult(attempted: RestoreResult.all)
    func restore(components: Int) async -> RestoreResult {
        restoredComponents.append(components)
        if suspendRestore {
            let result = await restore()
            return RestoreResult(attempted: components, fanError: result.0 ? nil : result.1 ?? "Restore failed")
        }
        return restoreResult
    }
    func setFanMode(_ mode: FanMode) async -> (Bool, String?) { (true, nil) }
    func setFanRPM(_ rpm: Int, index: Int) async -> (Bool, String?) { (true, nil) }
    func setFanTargets(_ targets: [(index: Int, rpm: Int)]) async -> (Bool, String?) { (true, nil) }
    func setChargeLimit(upper: Int, lower: Int) async -> (Bool, String?) { (true, nil) }
    func setCharging(_ on: Bool) async -> (Bool, String?) { (true, nil) }
    func setForceDischarge(_ on: Bool) async -> (Bool, String?) { (true, nil) }
}
