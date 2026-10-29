import AppKit
import Foundation
import SwiftUI

struct LocalSensorSnapshot: @unchecked Sendable {
    let power: SensorReader.PowerInfo
    let fans: [FanChannel]
    let temperatures: [TempReading]
}

typealias LocalSensorLoader = @Sendable (_ includeFallback: Bool) -> LocalSensorSnapshot

private let defaultLocalSensorLoader: LocalSensorLoader = { includeFallback in
    LocalSensorSnapshot(
        power: SensorReader.power(),
        fans: includeFallback ? SensorReader.fans() : [],
        temperatures: includeFallback ? SensorReader.temps() : []
    )
}

/// Owns XPC lifecycle, polling, helper installation, temperature state, and cross-cutting actions.
@MainActor
final class ThermalViewModel: ObservableObject, ViewModelHost {
    @Published var connectionState: HelperConnectionState = .disconnected
    @Published var helperStatusText = L10n.t("status.disconnected")
    @Published var smAppServiceState = "notRegistered"
    @Published var lastError: String?
    @Published var selectedDashboardTab: DashboardTab = .overview
    @Published private(set) var isQuitting = false
    @Published private(set) var failedRestoreComponents = 0
    @Published var temps: [TempReading] = []
    @Published private(set) var temperaturesUnavailable = true
    @Published var startAtLogin = HelperInstallService.startAtLoginEnabled()

    let fan: FanViewModel
    let battery: BatteryViewModel
    let power = PowerViewModel()

    private let xpc: any ThermalOrchestrationClient
    private let alerts: AlertPresenter
    private let loadLocalSensors: LocalSensorLoader
    private var started = false
    @Published private(set) var isInstallingHelper = false
    private struct SessionTasks {
        var helper: Task<Void, Never>?
        var restore: Task<Void, Never>?
        var refresh: Task<Void, Never>?
        var heartbeat: Task<Void, Never>?
        var reconnect: Task<Void, Never>?
        var recovery: Task<Void, Never>?
        var wake: Task<Void, Never>?
        var burst: Task<Void, Never>?
        var localSensor: Task<Void, Never>?

        mutating func cancelAll() {
            helper?.cancel(); helper = nil
            restore?.cancel(); restore = nil
            refresh?.cancel(); refresh = nil
            heartbeat?.cancel(); heartbeat = nil
            reconnect?.cancel(); reconnect = nil
            recovery?.cancel(); recovery = nil
            wake?.cancel(); wake = nil
            burst?.cancel(); burst = nil
            localSensor?.cancel(); localSensor = nil
        }
    }
    private var tasks = SessionTasks()
    private let session = ThermalSession()
    private var restoreGeneration = 0
    private var refreshPending = false
    private var refreshSeq = 0
    private var reconnectSeq = 0
    private var localSensorPending = false
    private var localSensorNeedsFallback = false
    private var localSensorNeedsPowerSample = false
    private var localSensorGeneration = 0
    private var menuVisible: Bool { session.menuVisible }
    private var dashboardVisible: Bool { session.dashboardVisible }
    var isMenuVisible: Bool { menuVisible }
    var isDashboardVisible: Bool { dashboardVisible }
    private var sleeping = false

    convenience init() {
        self.init(
            xpc: XPCClient(),
            alerts: AlertPresenter(),
            loadLocalSensors: defaultLocalSensorLoader
        )
    }

    init(
        xpc: any ThermalOrchestrationClient,
        alerts: AlertPresenter,
        loadLocalSensors: @escaping LocalSensorLoader = defaultLocalSensorLoader
    ) {
        self.xpc = xpc
        self.alerts = alerts
        self.loadLocalSensors = loadLocalSensors
        fan = FanViewModel(xpc: xpc)
        battery = BatteryViewModel(xpc: xpc)
        fan.host = self
        battery.host = self
        session.onRefresh = { [weak self] in self?.refresh() }
        session.onHeartbeat = { [weak self] in self?.beat() }
        session.onPowerSample = { [weak self] in self?.samplePowerHistory() }
        session.onSleep = { [weak self] in self?.prepareForSleep() }
        session.onWake = { [weak self] in self?.recoverAfterWake() }
        self.xpc.onConnectionLost = { [weak self] in
            Task { @MainActor in self?.handleConnectionLost() }
        }
    }

    // MARK: - ViewModelHost

    var isConnecting: Bool { connectionState == .connecting }
    var isConnected: Bool { connectionState == .connected && !isQuitting }
    var controlsEnabled: Bool { isConnected }

    func noteError(_ message: String) { lastError = message }

    func surfaceError(_ message: String) {
        lastError = message
        alerts.presentError(message)
    }

    func clearError() { lastError = nil }

    func batteryChargeDidChange() { burstPowerSamples() }

#if DEBUG
    var isRefreshInFlightForTesting: Bool { tasks.refresh != nil }
    var hasPendingRefreshForTesting: Bool { refreshPending }
    var reconnectGenerationForTesting: Int { reconnectSeq }
    var isSleepingForTesting: Bool { sleeping }
    var isLocalSensorReadInFlightForTesting: Bool { tasks.localSensor != nil }
    var isHeartbeatInFlightForTesting: Bool { tasks.heartbeat != nil }

    func prepareForSleepForTesting() { prepareForSleep() }
    func scheduleLocalSensorsForTesting(includeFallback: Bool) {
        scheduleLocalSensors(includeFallback: includeFallback)
    }
#endif
}

extension ThermalViewModel {
    // MARK: - Lifecycle

    func start() {
        guard !HelperMaintenance.isRequested(ProcessInfo.processInfo.arguments) else { return }
        // App-hosted tests must never register a daemon or connect to live hardware.
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard !started else { return }
        started = true
        fan.loadSettings()
        battery.loadSettings()
        smAppServiceState = HelperInstallService.statusText(force: true)
        session.start()
        sleeping = false
        reconnect()
    }

    func setMenuVisible(_ visible: Bool) {
        guard session.menuVisible != visible else { return }
        objectWillChange.send()
        session.setVisibility(menu: visible)
    }

    func setDashboardVisible(_ visible: Bool) {
        guard session.dashboardVisible != visible else { return }
        objectWillChange.send()
        session.setVisibility(dashboard: visible)
        if !visible { tasks.burst?.cancel() }
    }

    func stop() {
        prepareForSleep()
        session.stop()
        xpc.invalidate()
        started = false
    }

    private func prepareForSleep() {
        sleeping = true
        temperaturesUnavailable = true
        temps = []
        tasks.cancelAll()
        session.pause()
        restoreGeneration += 1
        refreshPending = false
        refreshSeq += 1
        reconnectSeq += 1
        localSensorPending = false
        localSensorNeedsFallback = false
        localSensorNeedsPowerSample = false
        localSensorGeneration += 1
        fan.cancelPendingCommands()
        battery.cancelPendingCommands()
        connectionState = .disconnected
    }

    private func recoverAfterWake() {
        tasks.wake?.cancel()
        tasks.wake = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.xpc.invalidate()
            self.sleeping = false
            self.session.resume()
            self.reconnect()
        }
    }

    func reconnect() {
        guard !sleeping, !isQuitting else { return }
        tasks.reconnect?.cancel()
        reconnectSeq += 1
        let seq = reconnectSeq
        connectionState = .connecting
        helperStatusText = L10n.t("status.connecting")
        xpc.connect()
        refresh()
        tasks.reconnect = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard let self, !Task.isCancelled, self.reconnectSeq == seq else { return }
            if self.connectionState == .connecting {
                self.connectionState = .disconnected
                self.helperStatusText = L10n.t("status.need.sudo")
                self.scheduleLocalSensors(includeFallback: true)
            }
            self.tasks.reconnect = nil
            self.battery.cancelPendingCommands()
        }
    }

    func refresh() {
        guard !sleeping, !isQuitting, tasks.restore == nil else { return }
        guard tasks.refresh == nil else {
            refreshPending = true
            return
        }
        smAppServiceState = HelperInstallService.statusText()
        if smAppServiceState == "requiresApproval" && connectionState != .connected {
            connectionState = .needsApproval
            helperStatusText = L10n.t("status.approval")
        }
        refreshSeq += 1
        let seq = refreshSeq
        tasks.refresh = Task { @MainActor [weak self] in
            guard let self else { return }
            async let capabilitiesRequest = self.xpc.capabilities()
            async let fanStatusRequest = self.xpc.fanStatus()
            async let batteryStatusRequest = self.xpc.batteryStatus()
            async let temperaturesRequest = self.xpc.temps()
            let (cap, fanStatus, batteryStatus, temperatures) = await (
                capabilitiesRequest, fanStatusRequest, batteryStatusRequest, temperaturesRequest
            )
            guard !Task.isCancelled, self.refreshSeq == seq else {
                self.finishRefresh(seq: seq)
                return
            }
            if let cap {
                guard cap.protocolVersion == TC.protocolVersion else {
                    self.connectionState = .error
                    self.helperStatusText = L10n.t("error.protocol")
                    self.lastError = L10n.t("error.protocol")
                    self.finishRefresh(seq: seq)
                    return
                }
                guard fanStatus != nil || cap.fanCount == 0,
                      batteryStatus != nil || !cap.batteryPresent else {
                    self.connectionState = .error
                    self.helperStatusText = L10n.t("error.readback")
                    self.fan.cancelPendingCommands()
                    self.battery.cancelPendingCommands()
                    self.finishRefresh(seq: seq)
                    return
                }
                self.tasks.reconnect?.cancel()
                self.tasks.reconnect = nil
                self.connectionState = .connected
                self.helperStatusText = L10n.t("status.helper.v", cap.helperVersion)
                self.fan.apply(capabilities: cap)
                self.battery.apply(capabilities: cap)
                if let fanStatus { self.fan.apply(status: fanStatus) }
                if let batteryStatus { self.battery.apply(status: batteryStatus) }
                self.applyTemperatures(temperatures)
                self.battery.helperDidBecomeReady()
            } else {
                self.scheduleLocalSensors(includeFallback: true)
            }
            self.finishRefresh(seq: seq)
        }
        scheduleLocalSensors(includeFallback: connectionState != .connected)
    }

    private func finishRefresh(seq: Int) {
        guard refreshSeq == seq else { return }
        tasks.refresh = nil
        if sleeping {
            refreshPending = false
            return
        }
        guard refreshPending else { return }
        refreshPending = false
        refresh()
    }

    private func scheduleLocalSensors(includeFallback: Bool, recordPower: Bool = false) {
        guard !sleeping else { return }
        localSensorNeedsFallback = localSensorNeedsFallback || includeFallback
        localSensorNeedsPowerSample = localSensorNeedsPowerSample || recordPower
        if tasks.localSensor != nil {
            localSensorPending = true
            return
        }
        let fallback = localSensorNeedsFallback
        let shouldRecordPower = localSensorNeedsPowerSample
        localSensorNeedsFallback = false
        localSensorNeedsPowerSample = false
        localSensorGeneration += 1
        let generation = localSensorGeneration
        let loadLocalSensors = self.loadLocalSensors
        tasks.localSensor = Task { @MainActor [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                loadLocalSensors(fallback)
            }.value
            guard let self,
                  self.localSensorGeneration == generation,
                  !Task.isCancelled,
                  !self.sleeping else { return }
            self.battery.apply(power: snapshot.power)
            if fallback, self.connectionState != .connected {
                self.fan.applyLocalFans(snapshot.fans)
                self.applyTemperatures(snapshot.temperatures)
            }
            if shouldRecordPower, self.dashboardVisible, snapshot.power.available {
                self.power.sample(
                    inWatts: self.battery.systemInWatts,
                    usageWatts: self.battery.usageWatts,
                    adapterCap: self.battery.adapterWatts
                )
            }
            self.tasks.localSensor = nil
            guard self.localSensorPending else { return }
            self.localSensorPending = false
            self.scheduleLocalSensors(
                includeFallback: self.localSensorNeedsFallback,
                recordPower: self.localSensorNeedsPowerSample
            )
        }
    }

    private func applyTemperatures(_ incoming: [TempReading]) {
        var byKey: [String: TempReading] = [:]
        for reading in incoming where reading.celsius > 1 { byKey[reading.key] = reading }
        let ordered = TC.tempKeys.compactMap { byKey[$0] }
        temperaturesUnavailable = ordered.isEmpty
        temps = ordered
    }

    // MARK: - Power sampling

    func samplePowerHistory() {
        scheduleLocalSensors(includeFallback: connectionState != .connected, recordPower: true)
    }

    func burstPowerSamples() {
        guard dashboardVisible else { return }
        samplePowerHistory()
        tasks.burst?.cancel()
        tasks.burst = Task { @MainActor [weak self] in
            for _ in 0..<4 {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self?.samplePowerHistory()
            }
        }
    }

}

extension ThermalViewModel {
    // MARK: - Heartbeat

    private func handleConnectionLost() {
        guard started, !sleeping else { return }
        tasks.reconnect?.cancel()
        tasks.reconnect = nil
        tasks.refresh?.cancel()
        tasks.refresh = nil
        refreshPending = false
        refreshSeq += 1
        if connectionState != .needsApproval {
            connectionState = .disconnected
            helperStatusText = L10n.t("status.disconnected")
        }
        tasks.restore?.cancel()
        tasks.restore = nil
        restoreGeneration += 1
        fan.cancelPendingCommands()
        battery.cancelPendingCommands()
        tasks.recovery?.cancel()
        tasks.recovery = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, !self.sleeping else { return }
            self.reconnect()
        }
    }

    func beat() {
        guard tasks.heartbeat == nil else { return }
        tasks.heartbeat = Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await self.xpc.ping()
            guard !Task.isCancelled else { return }
            self.tasks.heartbeat = nil
            if !ok, self.connectionState == .connected {
                self.handleConnectionLost()
            }
        }
    }

    // MARK: - Helper installation / permissions

    func setStartAtLogin(_ on: Bool) {
        if HelperInstallService.setStartAtLogin(on) {
            startAtLogin = on
        } else {
            startAtLogin = HelperInstallService.startAtLoginEnabled()
            noteError(L10n.t("install.fail"))
        }
    }

    func openLoginItems() {
        HelperInstallService.openLoginItems()
        smAppServiceState = HelperInstallService.statusText(force: true)
    }

    func showHelperPermissionAlert(force: Bool = true) {
        guard !isInstallingHelper else { return }
        if !force, connectionState == .connected { return }
        alerts.presentHelperPermission { [weak self] choice in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch choice {
                case .allow:
                    self.helperStatusText = await HelperInstallService.registerDaemon(retrigger: true)
                    guard !Task.isCancelled, !self.sleeping else { return }
                    HelperInstallService.openLoginItems()
                    self.smAppServiceState = HelperInstallService.statusText(force: true)
                    if self.smAppServiceState == "requiresApproval" {
                        self.connectionState = .needsApproval
                        self.helperStatusText = L10n.t("status.approval")
                    }
                    self.reconnect()
                case .sudo:
                    self.isInstallingHelper = true
                    let ok = await HelperInstallService.installWithAdministrator()
                    self.isInstallingHelper = false
                    guard !self.sleeping else { return }
                    if ok {
                        self.helperStatusText = L10n.t("perm.sudo.ok")
                        self.reconnect()
                    } else {
                        self.surfaceError(L10n.t("install.fail"))
                    }
                case .later:
                    break
                }
            }
        }
    }

    // MARK: - Cross-cutting commands

    func openSettings() {
        selectedDashboardTab = .settings
        WindowLocator.bringDashboardForward()
    }

    func confirmRestoreSystem() {
        alerts.confirmRestore { [weak self] in self?.restoreSystem() }
    }

    func prepareToQuit() async -> Bool {
        guard !isQuitting else { return false }
        isQuitting = true
        defer { isQuitting = false }
        let hasOverride = fan.hasTransientOverride || battery.hasTransientOverride
        guard connectionState == .connected else {
            if hasOverride { noteError(L10n.t("error.readback")); return false }
            stop()
            return true
        }
        tasks.refresh?.cancel()
        tasks.refresh = nil
        refreshPending = false
        refreshSeq += 1
        tasks.reconnect?.cancel()
        tasks.reconnect = nil
        reconnectSeq += 1
        fan.cancelPendingCommands()
        battery.cancelPendingCommands()
        let result = await xpc.restore(components: RestoreResult.transient)
        guard result.succeeded else {
            noteError(result.message ?? L10n.t("error.readback"))
            return false
        }
        stop()
        return true
    }

    func quitApp() async {
        NSApp.terminate(nil)
    }

    func restoreSystem() {
        restoreSystem(components: RestoreResult.all)
    }

    func retryFailedRestore() {
        guard failedRestoreComponents != 0 else { return }
        restoreSystem(components: failedRestoreComponents)
    }

    private func restoreSystem(components: Int) {
        guard isConnected, !sleeping, tasks.restore == nil else { return }
        tasks.refresh?.cancel()
        tasks.refresh = nil
        refreshPending = false
        refreshSeq += 1
        fan.cancelPendingCommands()
        battery.cancelPendingCommands()
        restoreGeneration += 1
        let generation = restoreGeneration
        connectionState = .restoring
        helperStatusText = L10n.t("status.restoring")
        tasks.restore = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.xpc.restore(components: components)
            guard !Task.isCancelled, self.restoreGeneration == generation, !self.sleeping else { return }
            self.tasks.restore = nil
            self.connectionState = .connected
            self.failedRestoreComponents = result.failedComponents
            self.lastError = result.message
            self.refresh()
        }
    }
}
