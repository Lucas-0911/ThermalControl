import Foundation
import SwiftUI

enum ChargeUIMode: String {
    case full, custom
}

/// Telemetry and confirmed policy remain separate from numeric editor drafts.
@MainActor
final class BatteryViewModel: ObservableObject {
    @Published var batteryPresent = false
    @Published var batteryPercent = 0
    @Published var amperageMA: Double = 0
    @Published var voltageMV: Double = 0
    @Published var adapterWatts: Double = 0
    @Published var systemInWatts: Double = 0
    @Published var adapterName: String?
    @Published var externalAC = false
    @Published var batteryControl = false
    @Published var forceDischargeControl = false
    @Published private(set) var powerUnavailable = true
    @Published private(set) var hasConfirmedChargeState = false
    @Published var chargeUpper = ChargeLimits.defaults.upper
    @Published var chargeLower = ChargeLimits.defaults.lower
    @Published var savedChargeUpper = ChargeLimits.defaults.upper
    @Published var draftChargeLower = ChargeLimits.defaults.lower
    @Published var chargingEnabled = true
    @Published var maintainActive = false
    @Published var forceDischarge = false
    @Published var chargeMode: ChargeUIMode = .full
    @Published var editingCharge = false
    @Published private(set) var applyingCharge = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var canControlCharge = false
    @Published private(set) var canForceDischarge = false
    @Published private(set) var dischargeTargetPercent = -1
    @Published private(set) var dischargeRemainingSeconds: TimeInterval = 0
    @Published private(set) var dischargeStopVerified = true
    @Published private(set) var dischargeStopReason: String?

    weak var host: (any ViewModelHost)?
    private let xpc: any ThermalHelperClient
    private var commandTask: Task<Void, Never>?
    private var chargeSeq = 0
    private var dischargeMayBeActive = false

    var hasTransientOverride: Bool { forceDischarge || dischargeMayBeActive }
    private var committedLimits = ChargeLimits.defaults
    private enum ChargeIntent {
        case full
        case custom(ChargeLimits)
        case discharge(Bool)
    }

    init(xpc: any ThermalHelperClient) { self.xpc = xpc }

    var showBattery: Bool { batteryPresent }
    var batteryWatts: Double { (amperageMA * voltageMV) / 1_000_000.0 }
    var usageWatts: Double {
        let inW = max(0, systemInWatts)
        let chargeW = max(0, batteryWatts)
        let drainW = max(0, -batteryWatts)
        return externalAC ? max(0, inW + drainW - chargeW) : drainW
    }

    var chargeStatusLabel: String {
        if forceDischarge { return L10n.t("charge.force") }
        if maintainActive { return L10n.t("charge.range", chargeUpper, chargeLower) }
        if !chargingEnabled { return L10n.t("charge.off") }
        return L10n.t("charge.full")
    }

    var powerInLabel: String {
        if !externalAC { return L10n.t("power.none") }
        if systemInWatts >= 0.3 { return L10n.t("power.in", systemInWatts) }
        if adapterWatts > 0 { return L10n.t("power.adapter", adapterWatts) }
        return L10n.t("power.plugged")
    }

    var canStartDischarge: Bool {
        host?.isConnected == true && hasConfirmedChargeState && batteryControl && forceDischargeControl
            && canForceDischarge && maintainActive && externalAC && batteryPercent > chargeUpper
            && !forceDischarge && dischargeStopVerified && !applyingCharge
    }

    var needsDischargeStop: Bool { forceDischarge || dischargeMayBeActive || !dischargeStopVerified }
    var isDischargeStopPending: Bool {
        !dischargeStopVerified && (dischargeStopReason != nil || !forceDischarge || errorMessage != nil)
    }

    var dischargeStopLabel: String {
        switch dischargeStopReason {
        case "deadline": return L10n.t("battery.force.reason.deadline")
        case "targetReached": return L10n.t("battery.force.reason.target")
        case "unplugged": return L10n.t("battery.force.reason.unplugged")
        case "untrustedIO", "sessionMissing": return L10n.t("battery.force.reason.safety")
        case "startFailed": return L10n.t("battery.force.reason.startFailed")
        default: return L10n.t("battery.force.stopped")
        }
    }

    func loadSettings() {
        committedLimits = ChargeLimits(
            upper: AppSettings.chargeUpper ?? ChargeLimits.defaults.upper,
            lower: AppSettings.chargeLower ?? ChargeLimits.defaults.lower
        )
        savedChargeUpper = committedLimits.upper
        draftChargeLower = committedLimits.lower
        // ponytail: saved settings seed drafts, never claim the helper has applied them.
    }

    func apply(capabilities cap: Capabilities) {
        batteryPresent = cap.batteryPresent
        batteryControl = cap.batteryControl
        forceDischargeControl = cap.forceDischargeControl
    }

    func apply(status st: BatteryStatus) {
        hasConfirmedChargeState = true
        batteryPresent = st.present
        batteryPercent = st.percent
        amperageMA = st.amperageMA
        voltageMV = st.voltageMV
        externalAC = st.externalAC
        chargeMode = st.maintainActive ? .custom : .full
        chargeUpper = st.upperLimit
        chargeLower = st.lowerLimit
        chargingEnabled = st.chargingEnabled
        maintainActive = st.maintainActive
        forceDischarge = st.forceDischarge
        canControlCharge = st.canControlCharge
        canForceDischarge = st.canForceDischarge
        dischargeTargetPercent = st.dischargeTargetPercent
        dischargeRemainingSeconds = st.dischargeRemainingSeconds.isFinite
            ? min(3_600, max(0, st.dischargeRemainingSeconds)) : 0
        dischargeStopVerified = st.dischargeStopVerified
        dischargeStopReason = st.dischargeStopReason
        if st.forceDischarge { dischargeMayBeActive = true }
        if !st.forceDischarge && st.dischargeStopVerified { dischargeMayBeActive = false }
        if st.maintainActive {
            committedLimits = ChargeLimits(upper: st.upperLimit, lower: st.lowerLimit)
            if !editingCharge {
                savedChargeUpper = committedLimits.upper
                draftChargeLower = committedLimits.lower
            }
        }
        if let error = st.lastError, !error.isEmpty, errorMessage == nil { errorMessage = error }
    }

    func helperDidBecomeReady() {
        // Reconnection observes state only. A disconnected click never becomes a later write.
    }

    func apply(power p: SensorReader.PowerInfo) {
        powerUnavailable = !p.available
        guard p.available else { return }
        adapterWatts = p.adapterRatedW
        systemInWatts = p.systemInW
        adapterName = p.adapterName
        if p.voltageMV > 0 { voltageMV = p.voltageMV }
        amperageMA = p.batteryMA
        externalAC = p.ac
        if p.present {
            batteryPresent = true
            batteryPercent = p.percent
        }
    }

    var chargePercentBinding: Binding<Int> {
        Binding(get: { self.savedChargeUpper }, set: {
            self.savedChargeUpper = ChargeLimits.clampUpper($0)
            self.editingCharge = true
        })
    }

    var chargeLowerBinding: Binding<Int> {
        Binding(get: { self.draftChargeLower }, set: {
            self.draftChargeLower = ChargeLimits(upper: self.savedChargeUpper, lower: $0).lower
            self.editingCharge = true
        })
    }

    func cancelPendingCommands() {
        commandTask?.cancel()
        commandTask = nil
        chargeSeq += 1
        applyingCharge = false
        hasConfirmedChargeState = false
    }

    func beginChargeEdits() { editingCharge = true }

    func cancelChargeEdits() {
        savedChargeUpper = committedLimits.upper
        draftChargeLower = committedLimits.lower
        editingCharge = false
    }

    func setChargeFull() { submit(.full) }

    func setChargeCustom(_ percent: Int? = nil) {
        let limits = percent.map { ChargeLimits(upper: $0, lower: committedLimits.lower) } ?? committedLimits
        submit(.custom(limits))
    }

    func applyChargeLimit() {
        clampChargeDraft()
        submit(.custom(ChargeLimits(upper: savedChargeUpper, lower: draftChargeLower)))
    }

    func clampChargeDraft() {
        let limits = ChargeLimits(upper: savedChargeUpper, lower: draftChargeLower)
        savedChargeUpper = limits.upper
        draftChargeLower = limits.lower
    }

    func setChargeLimit(upper: Int, lower: Int) {
        submit(.custom(ChargeLimits(upper: upper, lower: lower)))
    }

    static let menuPresetUppers = [60, 80, 90]

    func menuPresetIsSelected(upper: Int) -> Bool {
        chargeMode == .custom && chargeUpper == upper
    }

    func applyMenuPreset(upper: Int) {
        setChargeLimit(upper: upper, lower: upper - 10)
    }

    /// Limit on the menu bar. A saved 60/80/90 stays. Anything else starts at 60.
    func selectMenuLimit() {
        if chargeMode == .custom { return }
        let saved = AppSettings.chargeUpper
        let upper = saved.flatMap { Self.menuPresetUppers.contains($0) ? $0 : nil } ?? Self.menuPresetUppers[0]
        applyMenuPreset(upper: upper)
    }

    func setForceDischarge(_ on: Bool) {
        if on {
            guard canStartDischarge else {
                errorMessage = L10n.t("battery.force.precondition")
                return
            }
        } else {
            guard host?.isConnected == true else {
                errorMessage = L10n.t("error.xpc")
                return
            }
        }
        submit(.discharge(on))
    }

    private func submit(_ intent: ChargeIntent) {
        guard host?.isConnected == true else { return }
        if case .discharge(false) = intent {
            // Stop remains available even if capability probing or another command failed.
        } else {
            guard batteryControl, hasConfirmedChargeState, canControlCharge else { return }
        }
        errorMessage = nil
        if case .discharge(true) = intent { dischargeMayBeActive = true }
        chargeSeq += 1
        let seq = chargeSeq
        applyingCharge = true
        let previousTask = commandTask
        commandTask = Task { @MainActor [weak self] in
            await previousTask?.value
            guard let self, !Task.isCancelled, self.chargeSeq == seq else { return }
            let result: (Bool, String?)
            switch intent {
            case .full:
                let stop = self.forceDischargeControl || self.needsDischargeStop
                    ? await self.xpc.setForceDischarge(false) : (true, nil as String?)
                guard !Task.isCancelled, self.chargeSeq == seq else { return }
                result = stop.0 ? await self.xpc.setCharging(true) : stop
            case .custom(let limits):
                result = await self.xpc.setChargeLimit(upper: limits.upper, lower: limits.lower)
            case .discharge(let on):
                if on {
                    guard self.hasConfirmedChargeState, self.maintainActive, self.externalAC,
                          self.batteryPercent > self.chargeUpper else {
                        self.applyingCharge = false
                        self.commandTask = nil
                        self.errorMessage = L10n.t("battery.force.precondition")
                        return
                    }
                    self.dischargeStopVerified = false
                }
                result = await self.xpc.setForceDischarge(on)
            }
            guard !Task.isCancelled, self.chargeSeq == seq else { return }
            let status = await self.xpc.batteryStatus()
            guard !Task.isCancelled, self.chargeSeq == seq else { return }
            self.applyingCharge = false
            self.commandTask = nil
            guard let status else {
                self.hasConfirmedChargeState = false
                self.errorMessage = result.1 ?? L10n.t("error.readback")
                return
            }
            let matches = self.matches(intent, status: status)
            self.apply(status: status)
            guard result.0, matches else {
                self.errorMessage = result.1 ?? L10n.t("error.readback")
                return
            }
            self.errorMessage = nil
            switch intent {
            case .full:
                AppSettings.chargeMode = ChargeUIMode.full.rawValue
            case .custom(let limits):
                AppSettings.chargeMode = ChargeUIMode.custom.rawValue
                AppSettings.chargeUpper = limits.upper
                AppSettings.chargeLower = limits.lower
                AppSettings.savedChargeUpper = limits.upper
                if self.savedChargeUpper == limits.upper, self.draftChargeLower == limits.lower {
                    self.editingCharge = false
                }
            case .discharge: break
            }
            self.host?.batteryChargeDidChange()
        }
    }

    private func matches(_ intent: ChargeIntent, status: BatteryStatus) -> Bool {
        guard status.lastError?.isEmpty != false else { return false }
        switch intent {
        case .full:
            return !status.maintainActive && status.upperLimit == 100
                && !status.forceDischarge && status.dischargeStopVerified
        case .custom(let limits):
            return status.maintainActive && status.upperLimit == limits.upper && status.lowerLimit == limits.lower
        case .discharge(true):
            return status.forceDischarge && status.dischargeTargetPercent == status.upperLimit
                && status.dischargeRemainingSeconds > 0
        case .discharge(false):
            return !status.forceDischarge && status.dischargeStopVerified
        }
    }
}
