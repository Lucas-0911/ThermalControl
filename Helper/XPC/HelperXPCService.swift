import Foundation
import os

/// `ThermalHelperProtocol` implementation + policy persistence + boot
/// sequence. Extracted from the old `HelperDelegate` god object (Phase 3c);
/// per-method logic is unchanged. Dependencies arrive through the
/// `FanControlling`/`BatteryControlling`/`SMCProtocol` seams so the service
/// can be exercised with fakes.
final class HelperXPCService: NSObject, ThermalHelperProtocol {
    let smc: any SMCProtocol
    let fan: any FanControlling
    let battery: any BatteryControlling
    let watchdog: SafetyWatchdog
    private let power = PowerObserver()

    init(smc: any SMCProtocol, fan: any FanControlling, battery: any BatteryControlling, watchdog: SafetyWatchdog) {
        self.smc = smc
        self.fan = fan
        self.battery = battery
        self.watchdog = watchdog
        super.init()
    }

    /// Open SMC, probe hardware, start the watchdog + sleep/wake observer and
    /// restore the persisted policy. Called once from `main.swift`.
    func boot() {
        do {
            try smc.open()
            fan.probe()
            battery.probe()
            Task { [weak self] in
                guard let self else { return }
                await watchdog.setSafetyFallback { [weak self] in self?.persist() }
                await watchdog.start()
            }
            power.onSleep = { [weak self] in
                guard let self else { return }
                _ = self.fan.restoreSystem()
                self.battery.disableForceDischarge()
                Task { await self.watchdog.onSleep() }
            }
            power.onWake = { [weak self] in
                guard let self else { return }
                Task { await self.watchdog.onWake() }
            }
            power.start()
            restorePersisted()
            let fanN = fan.count
            let batFamily = battery.family.rawValue
            Logger.helper.info("fans=\(fanN, privacy: .public) battery=\(batFamily, privacy: .public)")
        } catch {
            Logger.helper.error("SMC \(error.localizedDescription, privacy: .public)")
        }
    }

    func restoreAll() {
        _ = fan.restoreSystem()
        battery.restoreDefaultCharge()
        persist()
    }

    private func persist() {
        let st = fan.status()
        let bat = battery.status()
        let manual: Int
        if case .manual(let targets) = fan.policy {
            manual = targets.sorted(by: { $0.key < $1.key }).first?.value ?? Int(st.fans.first?.targetRPM ?? 2500)
        } else {
            manual = Int(st.fans.first?.targetRPM ?? 2500)
        }
        StateStore.save(PersistedState(
            fanMode: st.desiredMode,
            manualRPM: manual,
            maintain: bat.maintainActive,
            upper: bat.upperLimit,
            lower: bat.lowerLimit,
            chargingEnabled: bat.chargingEnabled,
            forceDischarge: bat.forceDischarge,
            persistEnabled: true
        ).safeForPersistence)
    }

    private func restorePersisted() {
        // Boot always starts from hardware-safe transient baselines, even with
        // no state file. The app must explicitly send any forced override.
        _ = fan.restoreSystem()
        _ = battery.setForceDischarge(false)
        guard let s = StateStore.load(), s.persistEnabled else { return }
        if s.maintain {
            _ = battery.setLimit(upper: s.upper, lower: s.lower)
        } else {
            _ = battery.setChargingEnabled(s.chargingEnabled)
        }
        persist() // sanitize legacy state that may contain transient overrides
        Logger.state.info("restored persisted charge policy with safe fan baseline")
    }

    // MARK: - ThermalHelperProtocol

    func ping(_ token: String, reply: @escaping (Bool) -> Void) {
        Task { await watchdog.heartbeat() }
        reply(true)
    }

    func getCapabilities(reply: @escaping (Capabilities) -> Void) {
        Task { await watchdog.heartbeat() }
        let bat = battery.status()
        reply(Capabilities(
            fanCount: fan.count, fanControl: fan.canControl, ftstPresent: fan.ftstPresent,
            batteryPresent: bat.present, batteryControl: battery.canControl,
            batteryFamily: battery.family.rawValue, helperVersion: TC.helperVersion,
            protocolVersion: TC.protocolVersion
        ))
    }

    func getFanStatus(reply: @escaping (FanStatus) -> Void) {
        Task { await watchdog.heartbeat() }
        reply(fan.status())
    }

    func setFanMode(_ mode: Int, reply: @escaping (Bool, String?) -> Void) {
        Task { await watchdog.heartbeat() }
        let r = fan.setMode(FanMode(rawValue: mode) ?? .system)
        persist()
        reply(r.0, r.1)
    }

    func setFanTargetRPM(_ rpm: Int, fanIndex: Int, reply: @escaping (Bool, String?) -> Void) {
        Task { await watchdog.heartbeat() }
        let r = fan.setManual(rpm: rpm, index: fanIndex)
        persist()
        reply(r.0, r.1)
    }

    func getBatteryStatus(reply: @escaping (BatteryStatus) -> Void) {
        Task { await watchdog.heartbeat() }
        reply(battery.status())
    }

    func setChargeLimit(_ upper: Int, lower: Int, reply: @escaping (Bool, String?) -> Void) {
        Task { await watchdog.heartbeat() }
        let r = battery.setLimit(upper: upper, lower: lower)
        reply(r.0, r.1)
        persist()
    }

    func setChargingEnabled(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        Task { await watchdog.heartbeat() }
        let r = battery.setChargingEnabled(enabled)
        reply(r.0, r.1)
        persist()
    }

    func setForceDischarge(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        Task { await watchdog.heartbeat() }
        let r = battery.setForceDischarge(enabled)
        persist()
        reply(r.0, r.1)
    }

    func restoreSystemControl(reply: @escaping (Bool, String?) -> Void) {
        Task { await watchdog.heartbeat() }
        restoreAll()
        reply(true, nil)
    }

    func getThermalSnapshot(reply: @escaping ([TempReading]) -> Void) {
        Task { await watchdog.heartbeat() }
        var out: [TempReading] = []
        for k in TC.tempKeys {
            if let v = smc.readCelsius(k) {
                out.append(TempReading(key: k, celsius: v))
            }
        }
        reply(out)
    }
}