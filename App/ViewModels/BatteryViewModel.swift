import Foundation
import SwiftUI

enum ChargeUIMode: String {
    case full, custom
}

/// Battery + charge-limit + power-telemetry state, extracted from the
/// `ThermalViewModel` god object (Phase 4). Logic is behavior-identical;
/// clamping now routes through the shared `ChargeLimits` value type and
/// persistence through `AppSettings`.
@MainActor
final class BatteryViewModel: ObservableObject {
    // Battery identity / telemetry
    @Published var batteryPresent = false
    @Published var batteryPercent = 0
    @Published var amperageMA: Double = 0
    @Published var voltageMV: Double = 0
    @Published var adapterWatts: Double = 0
    @Published var systemInWatts: Double = 0
    @Published var adapterName: String?
    @Published var externalAC = false
    @Published var batteryControl = false

    // Charge state
    @Published var chargeUpper = 80
    @Published var chargeLower = 70
    @Published var savedChargeUpper = 80
    @Published var chargingEnabled = true
    @Published var maintainActive = false
    @Published var forceDischarge = false
    @Published var chargeMode: ChargeUIMode = .full
    @Published var editingCharge = false

    weak var host: (any ViewModelHost)?

    private let xpc: XPCClient
    private var chargeApplyTask: Task<Void, Never>?
    private var applyingCharge = false
    private var chargeSeq = 0

    init(xpc: XPCClient) {
        self.xpc = xpc
    }

    var showBattery: Bool {
        if batteryPresent { return true }
        return SensorReader.battery().present
    }

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

    // MARK: - Settings

    func loadSettings() {
        chargeUpper = AppSettings.chargeUpper ?? chargeUpper
        chargeLower = AppSettings.chargeLower ?? chargeLower
        let savedStop = AppSettings.savedChargeUpper
        savedChargeUpper = savedStop >= 20 ? savedStop : chargeUpper
        if AppSettings.chargeMode == ChargeUIMode.custom.rawValue {
            chargeMode = .custom
        }
    }

    // MARK: - Inbound state

    func apply(capabilities cap: Capabilities) {
        batteryPresent = cap.batteryPresent
        batteryControl = cap.batteryControl
    }

    func apply(status st: BatteryStatus) {
        batteryPresent = st.present
        batteryPercent = st.percent
        amperageMA = st.amperageMA
        voltageMV = st.voltageMV
        externalAC = st.externalAC
        if !editingCharge && !applyingCharge {
            forceDischarge = st.forceDischarge
            if chargeMode == .full {
                maintainActive = false
                chargingEnabled = true
            } else {
                maintainActive = true
                if st.upperLimit >= 20, st.upperLimit < 100 {
                    chargeUpper = st.upperLimit
                    savedChargeUpper = st.upperLimit
                }
                if st.lowerLimit >= 20, st.lowerLimit < chargeUpper {
                    chargeLower = st.lowerLimit
                }
            }
        }
    }

    func applyPowerSensors() {
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

    func applyLocalBattery() {
        let io = SensorReader.battery()
        if io.present {
            batteryPresent = true
            batteryPercent = io.percent
            externalAC = io.ac
        }
        applyPowerSensors()
    }

    // MARK: - Bindings

    var chargePercentBinding: Binding<Int> {
        Binding(
            get: { self.savedChargeUpper },
            set: { self.savedChargeUpper = ChargeLimits.clampUpper($0) }
        )
    }

    var chargeLowerBinding: Binding<Int> {
        Binding(
            get: { self.chargeLower },
            set: { self.chargeLower = min(98, max(20, $0)) }
        )
    }

    // MARK: - Commands

    func setChargeFull() {
        chargeApplyTask?.cancel()
        chargeMode = .full
        AppSettings.chargeMode = ChargeUIMode.full.rawValue
        applyingCharge = true
        maintainActive = false
        chargingEnabled = true
        forceDischarge = false
        setChargingEnabled(true)
    }

    func setChargeCustom(_ percent: Int? = nil) {
        chargeMode = .custom
        AppSettings.chargeMode = ChargeUIMode.custom.rawValue
        if let percent {
            savedChargeUpper = ChargeLimits.clampUpper(percent)
        }
        AppSettings.savedChargeUpper = savedChargeUpper
        applyChargeLimit()
    }

    func applyChargeLimit() {
        chargeApplyTask?.cancel()
        clampChargeDraft()
        setChargeLimit(upper: savedChargeUpper, lower: chargeLower)
    }

    func scheduleChargeApply() {
        guard host?.isConnected == true else {
            host?.surfaceError(L10n.t("error.xpc"))
            return
        }
        editingCharge = true
        chargeApplyTask?.cancel()
        chargeApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            self.editingCharge = false
            self.clampChargeDraft()
            self.setChargeLimit(upper: self.savedChargeUpper, lower: self.chargeLower)
        }
    }

    func scheduleChargeStop() {
        guard host?.isConnected == true else {
            host?.surfaceError(L10n.t("error.xpc"))
            return
        }
        editingCharge = true
        chargeApplyTask?.cancel()
        chargeApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            self.editingCharge = false
            self.setChargeCustom(self.savedChargeUpper)
        }
    }

    func clampChargeDraft() {
        let limits = ChargeLimits(upper: savedChargeUpper, lower: chargeLower)
        savedChargeUpper = limits.upper
        chargeUpper = limits.upper
        chargeLower = limits.lower
    }

    func setChargeLimit(upper: Int, lower: Int) {
        guard host?.isConnected == true else {
            host?.surfaceError(L10n.t("error.xpc"))
            return
        }
        let limits = ChargeLimits(upper: upper, lower: lower)
        chargeUpper = limits.upper
        chargeLower = limits.lower
        maintainActive = true
        chargeMode = .custom
        AppSettings.chargeMode = ChargeUIMode.custom.rawValue
        AppSettings.chargeUpper = limits.upper
        AppSettings.chargeLower = limits.lower
        editingCharge = false
        applyingCharge = true
        chargeSeq += 1
        let seq = chargeSeq
        Task { @MainActor [weak self] in
            guard let self else { return }
            let (ok, err) = await self.xpc.setChargeLimit(upper: limits.upper, lower: limits.lower)
            guard self.chargeSeq == seq else { return }
            self.applyingCharge = false
            if !ok {
                self.host?.surfaceError(err ?? L10n.t("error.cmd"))
            } else {
                self.host?.clearError()
                self.maintainActive = true
                self.host?.batteryChargeDidChange()
            }
        }
    }

    func setChargingEnabled(_ on: Bool) {
        applyingCharge = true
        chargingEnabled = on
        if on { maintainActive = false }
        chargeSeq += 1
        let seq = chargeSeq
        Task { @MainActor [weak self] in
            guard let self else { return }
            let (ok, err) = await self.xpc.setCharging(on)
            guard self.chargeSeq == seq else { return }
            self.applyingCharge = false
            if !ok {
                self.host?.surfaceError(err ?? L10n.t("error.cmd"))
            } else {
                self.host?.clearError()
                self.host?.batteryChargeDidChange()
            }
        }
    }

    func setForceDischarge(_ on: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let (ok, err) = await self.xpc.setForceDischarge(on)
            if !ok {
                self.host?.surfaceError(err ?? L10n.t("error.cmd"))
            } else {
                self.host?.clearError()
            }
        }
    }
}