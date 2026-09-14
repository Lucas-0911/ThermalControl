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
        Timer.scheduledTimer(withTimeInterval: TC.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.beat() }
        }
        Timer.scheduledTimer(withTimeInterval: TC.uiPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        samplePowerHistory()
        Timer.scheduledTimer(withTimeInterval: TC.powerSampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.samplePowerHistory() }
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
        smAppServiceState = HelperInstallService.statusText()
        if smAppServiceState == "requiresApproval" && connectionState != .connected {
            connectionState = .needsApproval
            helperStatusText = L10n.t("status.approval")
        }
        // Four independent XPC round-trips, fired concurrently (matches the
        // original completion-handler fan-out).
        Task { @MainActor [weak self] in
            guard let self, let cap = await self.xpc.capabilities() else { return }
            self.connectionState = .connected
            self.helperStatusText = L10n.t("status.helper.v", cap.helperVersion)
            self.fan.apply(capabilities: cap)
            self.battery.apply(capabilities: cap)
            self.lastError = nil
            if cap.helperVersion != TC.helperVersion, !self.askedHelperUpgrade {
                self.askedHelperUpgrade = true
                HelperInstallService.upgradeEmbeddedHelper()
                self.reconnect()
            }
        }
        Task { @MainActor [weak self] in
            guard let self, let st = await self.xpc.fanStatus() else { return }
            self.fan.apply(status: st)
        }
        Task { @MainActor [weak self] in
            guard let self, let st = await self.xpc.batteryStatus() else { return }
            self.battery.apply(status: st)
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let list = await self.xpc.temps()
            self.mergeTemps(list)
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
        samplePowerHistory()
        Task { @MainActor [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 200_000_000)
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