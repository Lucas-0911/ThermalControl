import AppKit
import Foundation
import SwiftUI

/// Orchestrator (Phase 4): owns the XPC connection lifecycle, timers, helper
/// installation flow, temps and cross-cutting actions. Fan/charge/power state
/// moved to `FanViewModel` / `BatteryViewModel` / `PowerViewModel`; alerts
/// moved to `AlertPresenter`. Views inject each sub-VM as its own
/// `@EnvironmentObject`.
@MainActor
final class ThermalViewModel: ObservableObject, ViewModelHost {
    @Published var connectionState: HelperConnectionState = .disconnected
    @Published var helperStatusText = L10n.t("status.disconnected")
    @Published var smAppServiceState = "notRegistered"
    @Published var lastError: String?
    @Published var temps: [TempReading] = []
    @Published var startAtLogin = HelperInstallService.startAtLoginEnabled()

    let fan: FanViewModel
    let battery: BatteryViewModel
    let power = PowerViewModel()

    private let xpc = XPCClient()
    private let alerts = AlertPresenter()
    private var started = false
    private var askedHelperUpgrade = false
    private var askedHelperPermission = false
    private var heartbeatTimer: Timer?
    private var telemetryTimer: Timer?
    private var powerTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshSeq = 0
    private var wakeTask: Task<Void, Never>?
    private var burstTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var menuVisible = false
    private var dashboardVisible = false
    private var sleeping = false

    init() {
        fan = FanViewModel(xpc: xpc)
        battery = BatteryViewModel(xpc: xpc)
        fan.host = self
        battery.host = self
    }

    // MARK: - ViewModelHost

    var isConnected: Bool { connectionState == .connected }
    var controlsEnabled: Bool { isConnected }

    func noteError(_ message: String) { lastError = message }

    func surfaceError(_ message: String) {
        lastError = message
        alerts.presentError(message)
    }

    func clearError() { lastError = nil }

    func batteryChargeDidChange() { burstPowerSamples() }

    // MARK: - Derived

    var hottestTemp: Double? { temps.map(\.celsius).max() }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        fan.loadSettings()
        battery.loadSettings()
        smAppServiceState = HelperInstallService.statusText()
        DispatchQueue.main.async {
            HelperInstallService.registerDaemon(retrigger: false)
        }
        reconnect()
        observeWorkspaceLifecycle()
        resumePolling()
    }

    func setMenuVisible(_ visible: Bool) {
        menuVisible = visible
        pollingModeDidChange()
    }

    func setDashboardVisible(_ visible: Bool) {
        dashboardVisible = visible
        pollingModeDidChange()
    }

    private var telemetryInterval: TimeInterval {
        if dashboardVisible { return TC.dashboardPollInterval }
        if menuVisible { return TC.menuPollInterval }
        return TC.backgroundPollInterval
    }

    private func pollingModeDidChange() {
        guard started, !sleeping else { return }
        scheduleTelemetryTimer()
        schedulePowerTimer()
        if menuVisible || dashboardVisible { refresh() }
    }

    private func resumePolling() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: TC.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.beat() }
        }
        scheduleTelemetryTimer()
        schedulePowerTimer()
    }

    private func scheduleTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: telemetryInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func schedulePowerTimer() {
        powerTimer?.invalidate()
        powerTimer = nil
        guard dashboardVisible else { return }
        samplePowerHistory()
        powerTimer = Timer.scheduledTimer(withTimeInterval: TC.powerSampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.samplePowerHistory() }
        }
    }

    private func suspendPolling() {
        heartbeatTimer?.invalidate()
        telemetryTimer?.invalidate()
        powerTimer?.invalidate()
        heartbeatTimer = nil
        telemetryTimer = nil
        powerTimer = nil
    }

    private func observeWorkspaceLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.prepareForSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.recoverAfterWake() }
            }
        ]
    }

    private func prepareForSleep() {
        sleeping = true
        suspendPolling()
        refreshTask?.cancel()
        refreshTask = nil
        refreshSeq += 1
        wakeTask?.cancel()
        burstTask?.cancel()
        fan.cancelPendingCommands()
        battery.cancelPendingCommands()
        connectionState = .disconnected
    }

    private func recoverAfterWake() {
        wakeTask?.cancel()
        wakeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.xpc.invalidate()
            self.sleeping = false
            self.resumePolling()
            self.reconnect()
        }
    }

    func reconnect() {
        connectionState = .connecting
        helperStatusText = L10n.t("status.connecting")
        xpc.connect()
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self else { return }
            if self.connectionState == .connecting {
                self.connectionState = .disconnected
                self.helperStatusText = L10n.t("status.need.sudo")
                self.applyLocalSensors()
            }
            self.promptHelperAccessIfNeeded()
        }
    }

    func refresh() {
        guard !sleeping, refreshTask == nil else { return }
        smAppServiceState = HelperInstallService.statusText()
        if smAppServiceState == "requiresApproval" && connectionState != .connected {
            connectionState = .needsApproval
            helperStatusText = L10n.t("status.approval")
        }
        refreshSeq += 1
        let seq = refreshSeq
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.refreshSeq == seq { self.refreshTask = nil }
            }
            async let capabilitiesRequest = self.xpc.capabilities()
            async let fanStatusRequest = self.xpc.fanStatus()
            async let batteryStatusRequest = self.xpc.batteryStatus()
            async let temperaturesRequest = self.xpc.temps()
            let (cap, fanStatus, batteryStatus, temperatures) = await (
                capabilitiesRequest, fanStatusRequest, batteryStatusRequest, temperaturesRequest
            )
            guard !Task.isCancelled else { return }
            guard let cap else {
                self.applyLocalSensors()
                return
            }
            self.connectionState = .connected
            self.helperStatusText = L10n.t("status.helper.v", cap.helperVersion)
            self.fan.apply(capabilities: cap)
            self.battery.apply(capabilities: cap)
            if let fanStatus { self.fan.apply(status: fanStatus) }
            if let batteryStatus { self.battery.apply(status: batteryStatus) }
            self.mergeTemps(temperatures)
            self.lastError = nil
            if cap.helperVersion != TC.helperVersion, !self.askedHelperUpgrade {
                self.askedHelperUpgrade = true
                HelperInstallService.upgradeEmbeddedHelper()
                self.reconnect()
            }
        }
        battery.applyPowerSensors()
        if connectionState != .connected {
            applyLocalSensors()
        }
    }

    private func applyLocalSensors() {
        battery.applyLocalBattery()
        if connectionState != .connected {
            fan.applyLocalFans(SensorReader.fans())
        }
        mergeTemps(temps)
    }

    private func mergeTemps(_ incoming: [TempReading]) {
        var byKey: [String: TempReading] = [:]
        for t in SensorReader.temps() { byKey[t.key] = t }
        for t in incoming where t.celsius > 1 { byKey[t.key] = t }
        let ordered = TC.tempKeys.compactMap { byKey[$0] }
        if !ordered.isEmpty { temps = ordered }
    }

    // MARK: - Power sampling

    func samplePowerHistory() {
        battery.applyPowerSensors()
        power.sample(
            inWatts: battery.systemInWatts,
            usageWatts: battery.usageWatts,
            adapterCap: battery.adapterWatts
        )
    }

    func burstPowerSamples() {
        guard dashboardVisible else { return }
        samplePowerHistory()
        burstTask?.cancel()
        burstTask = Task { @MainActor [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled else { return }
                self?.samplePowerHistory()
            }
        }
    }

    // MARK: - Heartbeat

    func beat() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let ok = await self.xpc.ping()
            if ok {
                if self.connectionState != .restoring { self.connectionState = .connected }
            } else if self.connectionState == .connected {
                self.connectionState = .disconnected
                self.helperStatusText = L10n.t("status.disconnected")
            }
        }
    }

    // MARK: - Helper installation / permissions

    func setStartAtLogin(_ on: Bool) {
        if HelperInstallService.setStartAtLogin(on) {
            startAtLogin = on
        } else {
            startAtLogin = HelperInstallService.startAtLoginEnabled()
        }
    }

    func installHelper() { showHelperPermissionAlert(force: true) }
    func openLoginItems() { HelperInstallService.openLoginItems() }

    func promptHelperAccessIfNeeded() {
        guard connectionState != .connected else { return }
        guard !askedHelperPermission else { return }
        askedHelperPermission = true
        helperStatusText = HelperInstallService.registerDaemon(retrigger: HelperInstallService.needsUserApproval())
        smAppServiceState = HelperInstallService.statusText()
        if smAppServiceState == "requiresApproval" {
            connectionState = .needsApproval
            helperStatusText = L10n.t("status.approval")
        }
        showHelperPermissionAlert(force: false)
    }

    func showHelperPermissionAlert(force: Bool = true) {
        if !force, connectionState == .connected { return }
        alerts.presentHelperPermission { [weak self] choice in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch choice {
                case .allow:
                    self.helperStatusText = HelperInstallService.registerDaemon(retrigger: true)
                    HelperInstallService.openLoginItems()
                    self.smAppServiceState = HelperInstallService.statusText()
                    if self.smAppServiceState == "requiresApproval" {
                        self.connectionState = .needsApproval
                        self.helperStatusText = L10n.t("status.approval")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        Task { @MainActor in self?.reconnect() }
                    }
                case .sudo:
                    let ok = HelperInstallService.installWithAdministrator()
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

    func restoreSystem() {
        connectionState = .restoring
        helperStatusText = L10n.t("status.restoring")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let (ok, err) = await self.xpc.restore()
            self.connectionState = ok ? .connected : .error
            if !ok {
                self.surfaceError(err ?? L10n.t("error.cmd"))
            } else {
                self.lastError = nil
                self.fan.desiredFanMode = .system
                self.battery.chargeMode = .full
            }
        }
    }

    // MARK: - Window / app

    func openDashboard() {
        if WindowLocator.dashboardWindow() != nil {
            WindowLocator.bringDashboardForward()
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible == false })?.makeKeyAndOrderFront(nil)
    }

    func quitApp() { NSApp.terminate(nil) }

    var menuTitle: String {
        if connectionState != .connected { return "TC" }
        if let rpm = fan.fans.first?.actualRPM, rpm > 0 { return "\(Int(rpm))" }
        if battery.batteryPresent { return "\(battery.batteryPercent)%" }
        return "TC"
    }

    var menuSymbol: String {
        if connectionState == .connected, fan.fans.isEmpty, battery.batteryPresent { return "battery.75" }
        return "fan"
    }
}