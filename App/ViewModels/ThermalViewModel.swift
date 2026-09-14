import AppKit
import Foundation
import SwiftUI

struct PowerSample: Identifiable, Equatable {
    let time: Date
    let watts: Double
    var id: Date { time }
}

@MainActor
final class ThermalViewModel: ObservableObject {
    @Published var connectionState: HelperConnectionState = .disconnected
    @Published var helperStatusText = L10n.t("status.disconnected")
    @Published var smAppServiceState = "notRegistered"
    @Published var lastError: String?

    @Published var fanCount = 0
    @Published var fans: [FanChannel] = []
    @Published var desiredFanMode: FanMode = .system
    @Published var manualRPM: Int = 2500
    @Published var fanControl = false

    @Published var batteryPresent = false
    @Published var batteryPercent = 0
    @Published var amperageMA: Double = 0
    @Published var voltageMV: Double = 0
    @Published var adapterWatts: Double = 0
    @Published var systemInWatts: Double = 0
    @Published var adapterName: String?
    @Published var externalAC = false
    @Published var chargeUpper = 80
    @Published var chargeLower = 70
    @Published var savedChargeUpper = 80
    @Published var chargingEnabled = true
    @Published var maintainActive = false
    @Published var forceDischarge = false
    @Published var batteryControl = false
    @Published var temps: [TempReading] = []
    @Published var fanDrafts: [Int: Int] = [:]
    @Published var editingFan = false
    @Published var editingCharge = false
    @Published var powerHistory: [PowerSample] = []
    @Published var usageHistory: [PowerSample] = []
    @Published var startAtLogin = HelperInstallService.startAtLoginEnabled()

    var sliderMin: Double { max(800, fans.first?.minRPM ?? 1000) }
    var sliderMax: Double { max(sliderMin + 100, fans.first?.maxRPM ?? 7000) }
    var hottestTemp: Double? { temps.map(\.celsius).max() }
    var batteryWatts: Double { (amperageMA * voltageMV) / 1_000_000.0 }
    /// System load: adapter in + battery drain − battery charge.
    var usageWatts: Double {
        let batW = batteryWatts
        let inW = max(0, systemInWatts)
        let chargeW = max(0, batW)
        let drainW = max(0, -batW)
        if !externalAC { return drainW }
        return max(0, inW + drainW - chargeW)
    }
    var chargeRangeLabel: String { "\(chargeLower)–\(chargeUpper)%" }
    enum ChargeUIMode: String { case full, custom }
    @Published var chargeMode: ChargeUIMode = .full

    var chargeIsFull: Bool { chargeMode == .full }
    var chargeStatusLabel: String {
        if forceDischarge { return L10n.t("charge.force") }
        if maintainActive { return L10n.t("charge.range", chargeUpper, chargeLower) }
        if !chargingEnabled { return L10n.t("charge.off") }
        return L10n.t("charge.full")
    }
    var powerInLabel: String {
        if !externalAC { return L10n.t("power.none") }
        if systemInWatts >= 0.3 {
            return L10n.t("power.in", systemInWatts)
        }
        if adapterWatts > 0 {
            return L10n.t("power.adapter", adapterWatts)
        }
        return L10n.t("power.plugged")
    }

    private let xpc = XPCClient()
    private var started = false
    private var fanApplyTask: Task<Void, Never>?
    private var chargeApplyTask: Task<Void, Never>?
    private var applyingNamedFanMode = false
    private var applyingCharge = false
    private var askedHelperUpgrade = false
    private var askedHelperPermission = false
    private var fanSeq = 0
    private var chargeSeq = 0
    private var alertQueued = false

    var controlsEnabled: Bool { connectionState == .connected }
    var showFan: Bool { fanCount > 0 || !fans.isEmpty }
    var showBattery: Bool {
        if batteryPresent { return true }
        return SensorReader.battery().present
    }

    func start() {
        guard !started else { return }
        started = true
        let d = UserDefaults.standard
        let saved = d.integer(forKey: "manualRPM")
        if saved > 0 { manualRPM = saved }
        chargeUpper = d.object(forKey: "chargeUpper") as? Int ?? chargeUpper
        chargeLower = d.object(forKey: "chargeLower") as? Int ?? chargeLower
        let savedStop = d.integer(forKey: "savedChargeUpper")
        savedChargeUpper = savedStop >= 20 ? savedStop : chargeUpper
        if d.string(forKey: "chargeMode") == ChargeUIMode.custom.rawValue {
            chargeMode = .custom
        }
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
        xpc.capabilities { [weak self] cap in
            Task { @MainActor in
                guard let self else { return }
                if let cap {
                    self.connectionState = .connected
                    self.helperStatusText = L10n.t("status.helper.v", cap.helperVersion)
                    self.fanCount = cap.fanCount
                    self.fanControl = cap.fanControl
                    self.batteryPresent = cap.batteryPresent
                    self.batteryControl = cap.batteryControl
                    self.lastError = nil
                    if cap.helperVersion != TC.helperVersion, !self.askedHelperUpgrade {
                        self.askedHelperUpgrade = true
                        HelperInstallService.upgradeEmbeddedHelper()
                        self.reconnect()
                    }
                }
            }
        }
        xpc.fanStatus { [weak self] st in
            Task { @MainActor in
                guard let self, let st else { return }
                self.fans = st.fans
                self.fanCount = st.fans.count
                if !self.applyingNamedFanMode && !self.editingFan {
                    let incoming = FanMode(rawValue: st.desiredMode) ?? .system
                    // Keep Custom selected even if helper hasn't switched yet.
                    if self.desiredFanMode != .manual {
                        self.desiredFanMode = incoming
                    }
                }
                if !self.editingFan && self.desiredFanMode == .manual {
                    for f in st.fans {
                        if self.fanDrafts[f.index] == nil {
                            self.fanDrafts[f.index] = Int((f.targetRPM > 0 ? f.targetRPM : f.actualRPM).rounded())
                        }
                    }
                }
                if let err = st.lastError, !err.isEmpty { self.lastError = err }
            }
        }
        xpc.batteryStatus { [weak self] st in
            Task { @MainActor in
                guard let self, let st else { return }
                self.batteryPresent = st.present
                self.batteryPercent = st.percent
                self.amperageMA = st.amperageMA
                self.voltageMV = st.voltageMV
                self.externalAC = st.externalAC
                if !self.editingCharge && !self.applyingCharge {
                    self.forceDischarge = st.forceDischarge
                    if self.chargeMode == .full {
                        self.maintainActive = false
                        self.chargingEnabled = true
                    } else {
                        self.maintainActive = true
                        if st.upperLimit >= 20, st.upperLimit < 100 {
                            self.chargeUpper = st.upperLimit
                            self.savedChargeUpper = st.upperLimit
                        }
                        if st.lowerLimit >= 20, st.lowerLimit < self.chargeUpper {
                            self.chargeLower = st.lowerLimit
                        }
                    }
                }
            }
        }
        xpc.temps { [weak self] list in
            Task { @MainActor in
                guard let self else { return }
                self.mergeTemps(list)
            }
        }
        applyPowerSensors()
        if connectionState != .connected {
            applyLocalSensors()
        }
    }

    private func applyLocalSensors() {
        let io = SensorReader.battery()
        if io.present {
            batteryPresent = true
            batteryPercent = io.percent
            externalAC = io.ac
        }
        applyPowerSensors()
        let localFans = SensorReader.fans()
        if !localFans.isEmpty && connectionState != .connected {
            fans = localFans
            fanCount = localFans.count
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

    func samplePowerHistory() {
        applyPowerSensors()
        let now = Date()
        let cutoff = now.addingTimeInterval(-TC.powerHistoryWindow)
        powerHistory.append(PowerSample(time: now, watts: max(0, systemInWatts)))
        powerHistory.removeAll { $0.time < cutoff }
        usageHistory.append(PowerSample(time: now, watts: usageWatts))
        usageHistory.removeAll { $0.time < cutoff }
    }

    func burstPowerSamples() {
        samplePowerHistory()
        Task { @MainActor in
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                self.samplePowerHistory()
            }
        }
    }

    var powerChartMax: Double { sparklineMax(powerHistory) }
    var usageChartMax: Double { sparklineMax(usageHistory) }

    private func sparklineMax(_ samples: [PowerSample]) -> Double {
        let peak = samples.map(\.watts).max() ?? 0
        let cap = max(adapterWatts, 20)
        return max(10, min(cap, max(peak * 1.25, 8)))
    }

    private func applyPowerSensors() {
        let p = SensorReader.power()
        adapterWatts = p.adapterRatedW
        systemInWatts = p.systemInW
        adapterName = p.adapterName
        if p.voltageMV > 0 { voltageMV = p.voltageMV }
        amperageMA = p.batteryMA
        if p.ac { externalAC = true }
        if p.present {
            batteryPresent = true
            if p.percent > 0 { batteryPercent = p.percent }
        }
    }

    func beat() {
        xpc.ping { [weak self] ok in
            Task { @MainActor in
                guard let self else { return }
                if ok {
                    if self.connectionState != .restoring { self.connectionState = .connected }
                } else if self.connectionState == .connected {
                    self.connectionState = .disconnected
                    self.helperStatusText = L10n.t("status.disconnected")
                }
            }
        }
    }

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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !force, self.connectionState == .connected { return }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L10n.t("perm.title")
            alert.informativeText = L10n.t("perm.body")
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.t("perm.allow"))
            alert.addButton(withTitle: L10n.t("perm.sudo"))
            alert.addButton(withTitle: L10n.t("perm.later"))
            let r = alert.runModal()
            switch r {
            case .alertFirstButtonReturn:
                self.helperStatusText = HelperInstallService.registerDaemon(retrigger: true)
                HelperInstallService.openLoginItems()
                self.smAppServiceState = HelperInstallService.statusText()
                if self.smAppServiceState == "requiresApproval" {
                    self.connectionState = .needsApproval
                    self.helperStatusText = L10n.t("status.approval")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.reconnect() }
            case .alertSecondButtonReturn:
                let ok = HelperInstallService.installWithAdministrator()
                if ok {
                    self.helperStatusText = L10n.t("perm.sudo.ok")
                    self.reconnect()
                } else {
                    self.presentError(L10n.t("install.fail"))
                }
            default:
                break
            }
        }
    }

    func setFanMode(_ mode: FanMode) {
        if mode == .manual {
            selectFanCustom()
            return
        }
        fanApplyTask?.cancel()
        editingFan = false
        fanSeq += 1
        let seq = fanSeq
        applyingNamedFanMode = true
        let prev = desiredFanMode
        desiredFanMode = mode
        xpc.setFanMode(mode) { [weak self] ok, err in
            Task { @MainActor in
                guard let self, self.fanSeq == seq else { return }
                self.applyingNamedFanMode = false
                if !ok {
                    self.desiredFanMode = prev
                    self.presentError(err ?? L10n.t("error.cmd"))
                } else {
                    self.lastError = nil
                }
            }
        }
    }

    func selectFanCustom() {
        fanApplyTask?.cancel()
        applyingNamedFanMode = false
        editingFan = false
        desiredFanMode = .manual
        for f in fans where fanDrafts[f.index] == nil {
            let seed = f.actualRPM > 0 ? f.actualRPM : sliderMin(for: f.index)
            fanDrafts[f.index] = Int(seed.rounded())
        }
        if manualRPM <= 0 { manualRPM = savedRPM(for: fans.first?.index ?? 0) }
        if fans.isEmpty && !controlsEnabled {
            presentError(L10n.t("error.xpc"))
            return
        }
        if !fans.isEmpty { setManualRPM() }
    }

    func setManualRPM() {
        fanApplyTask?.cancel()
        editingFan = false
        desiredFanMode = .manual
        if fans.count > 1 {
            for f in fans {
                setFanRPM(savedRPM(for: f.index), index: f.index)
            }
        } else {
            setFanRPM(manualRPM, index: -1)
        }
    }

    func scheduleFanApply(index: Int = -1) {
        desiredFanMode = .manual
        editingFan = true
        fanApplyTask?.cancel()
        fanApplyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            self.editingFan = false
            if index < 0 {
                self.setFanRPM(self.manualRPM, index: -1)
            } else {
                self.setFanRPM(self.draftRPM(for: index), index: index)
            }
        }
    }

    func setFanRPM(_ rpm: Int, index: Int) {
        applyingNamedFanMode = false
        desiredFanMode = .manual
        guard controlsEnabled else {
            presentError(L10n.t("error.xpc"))
            return
        }
        let lo = Int(sliderMin(for: index).rounded())
        let hi = Int(sliderMax(for: index).rounded())
        let clamped = min(max(rpm, lo), hi)
        if index < 0 {
            manualRPM = clamped
            UserDefaults.standard.set(clamped, forKey: "manualRPM")
            for f in fans { fanDrafts[f.index] = clamped }
        } else {
            fanDrafts[index] = clamped
        }
        fanSeq += 1
        let seq = fanSeq
        xpc.setFanRPM(clamped, index: index) { [weak self] ok, err in
            Task { @MainActor in
                guard let self, self.fanSeq == seq else { return }
                self.editingFan = false
                if !ok {
                    self.presentError(err ?? L10n.t("error.cmd"))
                } else {
                    self.lastError = nil
                }
            }
        }
    }

    func presentError(_ message: String, title: String? = nil) {
        lastError = message
        guard !alertQueued else { return }
        alertQueued = true
        let t = title ?? L10n.t("error.title")
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = t
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.t("ok"))
            alert.runModal()
            self?.alertQueued = false
        }
    }

    func sliderMin(for index: Int) -> Double {
        if let f = fans.first(where: { $0.index == index }) {
            return max(800, f.minRPM)
        }
        return sliderMin
    }

    func sliderMax(for index: Int) -> Double {
        let lo = sliderMin(for: index)
        if let f = fans.first(where: { $0.index == index }) {
            return max(lo + 100, f.maxRPM)
        }
        return sliderMax
    }

    func displayRPM(for fan: FanChannel) -> Double {
        switch desiredFanMode {
        case .quiet:
            return sliderMin(for: fan.index)
        case .max:
            return sliderMax(for: fan.index)
        case .manual:
            return Double(savedRPM(for: fan.index))
        case .system:
            return fan.actualRPM
        }
    }

    /// RPM shown in the number field for the current mode (not the saved custom, unless Custom is selected).
    var displayedModeRPM: Int {
        switch desiredFanMode {
        case .quiet: return Int(sliderMin.rounded())
        case .max: return Int(sliderMax.rounded())
        case .system: return Int((fans.first?.actualRPM ?? 0).rounded())
        case .manual: return manualRPM
        }
    }

    func displayedModeRPM(for index: Int) -> Int {
        if let f = fans.first(where: { $0.index == index }) {
            return Int(displayRPM(for: f).rounded())
        }
        return displayedModeRPM
    }

    /// User's last Custom RPM; never overwritten by Auto/Quiet/Max.
    func savedRPM(for index: Int) -> Int {
        if let v = fanDrafts[index] { return v }
        return manualRPM
    }

    var rpmFieldBinding: Binding<Int> {
        Binding(
            get: { self.desiredFanMode == .manual ? self.manualRPM : self.displayedModeRPM },
            set: { self.manualRPM = $0 }
        )
    }

    func rpmFieldBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: {
                self.desiredFanMode == .manual
                    ? self.savedRPM(for: index)
                    : self.displayedModeRPM(for: index)
            },
            set: { self.fanDrafts[index] = $0 }
        )
    }

    func draftRPM(for index: Int) -> Int {
        savedRPM(for: index)
    }

    var chargePercentBinding: Binding<Int> {
        Binding(
            get: { self.savedChargeUpper },
            set: { self.savedChargeUpper = min(99, max(20, $0)) }
        )
    }

    var chargeLowerBinding: Binding<Int> {
        Binding(
            get: { self.chargeLower },
            set: { self.chargeLower = min(98, max(20, $0)) }
        )
    }

    func setChargeFull() {
        chargeApplyTask?.cancel()
        chargeMode = .full
        UserDefaults.standard.set(ChargeUIMode.full.rawValue, forKey: "chargeMode")
        applyingCharge = true
        maintainActive = false
        chargingEnabled = true
        forceDischarge = false
        setChargingEnabled(true)
    }

    func setChargeCustom(_ percent: Int? = nil) {
        chargeMode = .custom
        UserDefaults.standard.set(ChargeUIMode.custom.rawValue, forKey: "chargeMode")
        if let percent {
            savedChargeUpper = min(99, max(20, percent))
        }
        UserDefaults.standard.set(savedChargeUpper, forKey: "savedChargeUpper")
        applyChargeLimit()
    }

    func setChargeStop(_ percent: Int) {
        let u = min(99, max(20, percent))
        chargeApplyTask?.cancel()
        chargeMode = .custom
        UserDefaults.standard.set(ChargeUIMode.custom.rawValue, forKey: "chargeMode")
        applyingCharge = true
        maintainActive = true
        chargingEnabled = true
        chargeUpper = u
        savedChargeUpper = u
        if chargeLower >= u {
            chargeLower = max(20, u - 5)
        }
        UserDefaults.standard.set(u, forKey: "savedChargeUpper")
        UserDefaults.standard.set(chargeLower, forKey: "chargeLower")
        applyChargeLimit()
    }

    func setMaintain70_80() { setChargePreset(lower: 70, upper: 80) }

    func setChargePreset(lower: Int, upper: Int) {
        chargeLower = lower
        chargeUpper = upper
        applyChargeLimit()
    }

    func applyChargeLimit() {
        chargeApplyTask?.cancel()
        clampChargeDraft()
        setChargeLimit(upper: savedChargeUpper, lower: chargeLower)
    }

    func scheduleChargeApply() {
        guard controlsEnabled else {
            presentError(L10n.t("error.xpc"))
            return
        }
        editingCharge = true
        chargeApplyTask?.cancel()
        chargeApplyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self.editingCharge = false
            self.clampChargeDraft()
            self.setChargeLimit(upper: self.savedChargeUpper, lower: self.chargeLower)
        }
    }

    func scheduleChargeStop() {
        guard controlsEnabled else {
            presentError(L10n.t("error.xpc"))
            return
        }
        editingCharge = true
        chargeApplyTask?.cancel()
        chargeApplyTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self.editingCharge = false
            self.setChargeCustom(self.savedChargeUpper)
        }
    }

    func clampChargeDraft() {
        savedChargeUpper = min(99, max(20, savedChargeUpper))
        chargeUpper = savedChargeUpper
        chargeLower = min(chargeUpper - 2, max(20, chargeLower))
    }

    func setChargeLimit(upper: Int, lower: Int) {
        guard controlsEnabled else {
            presentError(L10n.t("error.xpc"))
            return
        }
        let u = min(99, max(20, upper))
        let l = min(u - 2, max(20, lower))
        chargeUpper = u
        chargeLower = l
        maintainActive = true
        chargeMode = .custom
        UserDefaults.standard.set(ChargeUIMode.custom.rawValue, forKey: "chargeMode")
        UserDefaults.standard.set(u, forKey: "chargeUpper")
        UserDefaults.standard.set(l, forKey: "chargeLower")
        editingCharge = false
        applyingCharge = true
        chargeSeq += 1
        let seq = chargeSeq
        xpc.setChargeLimit(upper: u, lower: l) { [weak self] ok, err in
            Task { @MainActor in
                guard let self, self.chargeSeq == seq else { return }
                self.applyingCharge = false
                if !ok {
                    self.presentError(err ?? L10n.t("error.cmd"))
                } else {
                    self.lastError = nil
                    self.maintainActive = true
                    self.burstPowerSamples()
                }
            }
        }
    }

    func setChargingEnabled(_ on: Bool) {
        applyingCharge = true
        chargingEnabled = on
        if on { maintainActive = false }
        chargeSeq += 1
        let seq = chargeSeq
        xpc.setCharging(on) { [weak self] ok, err in
            Task { @MainActor in
                guard let self, self.chargeSeq == seq else { return }
                self.applyingCharge = false
                if !ok {
                    self.presentError(err ?? L10n.t("error.cmd"))
                } else {
                    self.lastError = nil
                    self.burstPowerSamples()
                }
            }
        }
    }

    func setForceDischarge(_ on: Bool) {
        xpc.setForceDischarge(on) { [weak self] ok, err in
            Task { @MainActor in
                guard let self else { return }
                if !ok { self.presentError(err ?? L10n.t("error.cmd")) }
                else { self.lastError = nil }
            }
        }
    }

    func restoreSystem() {
        connectionState = .restoring
        helperStatusText = L10n.t("status.restoring")
        xpc.restore { [weak self] ok, err in
            Task { @MainActor in
                guard let self else { return }
                self.connectionState = ok ? .connected : .error
                if !ok { self.presentError(err ?? L10n.t("error.cmd")) }
                else {
                    self.lastError = nil
                    self.desiredFanMode = .system
                    self.chargeMode = .full
                }
            }
        }
    }

    func openDashboard() {
        guard let existing = WindowLocator.dashboardWindow() else {
            // Fallback: surface any hidden main-able window (e.g. before the
            // dashboard title is attached).
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.canBecomeMain && $0.isVisible == false })?.makeKeyAndOrderFront(nil)
            return
        }
        _ = existing // keep the guard bound; bringDashboardForward refetches and orders front
        WindowLocator.bringDashboardForward()
    }

    func quitApp() { NSApp.terminate(nil) }

    var menuTitle: String {
        if connectionState != .connected { return "TC" }
        if let rpm = fans.first?.actualRPM, rpm > 0 { return "\(Int(rpm))" }
        if batteryPresent { return "\(batteryPercent)%" }
        return "TC"
    }

    var menuSymbol: String {
        if connectionState == .connected, fans.isEmpty, batteryPresent { return "battery.75" }
        return "fan"
    }
}
