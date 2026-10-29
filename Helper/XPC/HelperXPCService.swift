import Foundation
import os

/// XPC service, boot sequence, and persisted-policy owner.
final class HelperXPCService: NSObject, ThermalHelperProtocol {
    let smc: any SMCProtocol
    let fan: any FanControlling
    let battery: any BatteryControlling
    let watchdog: SafetyWatchdog
    private let power = PowerObserver()
    private let transactionLock: NSRecursiveLock
    private let saveState: (PersistedState) -> Result<Void, Error>
    private var persistenceError: String?

    init(
        smc: any SMCProtocol,
        fan: any FanControlling,
        battery: any BatteryControlling,
        watchdog: SafetyWatchdog,
        transactionLock: NSRecursiveLock,
        saveState: @escaping (PersistedState) -> Result<Void, Error> = { StateStore.save($0) }
    ) {
        self.smc = smc
        self.fan = fan
        self.battery = battery
        self.watchdog = watchdog
        self.transactionLock = transactionLock
        self.saveState = saveState
        super.init()
    }

    /// Open SMC, probe hardware, start the watchdog + sleep/wake observer and
    /// restore the persisted policy. Called once from `main.swift`.
    func boot() {
        do {
            try smc.open()
            let hardware = withTransaction {
                fan.probe()
                battery.probe()
                restorePersisted()
                return (fan.count, battery.family.rawValue)
            }
            Task { [weak self] in
                guard let self else { return }
                await watchdog.setSafetyFallback {
                    Logger.watchdog.notice("transient overrides released; saved charge intent retained")
                }
                await watchdog.start()
            }
            power.onSleep = { [weak self] in
                guard let self else { return }
                await self.watchdog.onSleep()
            }
            power.onWake = { [weak self] in
                guard let self else { return }
                await self.watchdog.onWake()
            }
            power.start()
            Logger.helper.info("fans=\(hardware.0, privacy: .public) battery=\(hardware.1, privacy: .public)")
        } catch {
            Logger.helper.error("SMC \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func restoreAll() -> (Bool, String?) {
        let result = restore(components: RestoreResult.all)
        return (result.succeeded, result.message)
    }

    /// Shutdown releases transient hardware without replacing the saved charge intent.
    func prepareForShutdown() -> RestoreResult {
        withTransaction {
            let fanResult = fan.restoreSystem()
            let dischargeResult = stopDischargeIfSupported()
            let chargeResult = battery.restoreDefaultCharge()
            return RestoreResult(
                attempted: RestoreResult.all,
                fanError: fanResult.0 ? nil : fanResult.1 ?? "Fan restore failed",
                chargeError: chargeResult.0 ? nil : chargeResult.1 ?? "Charge restore failed",
                dischargeError: dischargeResult.0 ? nil : dischargeResult.1 ?? "Discharge stop failed"
            )
        }
    }

    private func stopDischargeIfSupported() -> (Bool, String?) {
        let key = battery.family == .tahoe ? SMCKey.chIE : SMCKey.ch0I
        guard smc.keyExists(key.rawValue) || battery.status().forceDischarge else { return (true, nil) }
        return battery.stopForceDischarge()
    }

    private func restore(components: Int) -> RestoreResult {
        withTransaction {
            guard components > 0, components & ~RestoreResult.all == 0 else {
                return RestoreResult(attempted: RestoreResult.all, fanError: "Invalid restore components")
            }
            let fanResult = components & RestoreResult.fan == 0 ? (true, nil as String?) : fan.restoreSystem()
            let dischargeResult = components & RestoreResult.discharge == 0 ? (true, nil as String?) : stopDischargeIfSupported()
            let chargeResult = components & RestoreResult.charge == 0 ? (true, nil as String?) : battery.restoreDefaultCharge()
            let saved = components & RestoreResult.charge == 0 ? nil : persist()
            return RestoreResult(
                attempted: components,
                fanError: fanResult.0 ? nil : fanResult.1 ?? "Fan restore failed",
                chargeError: !chargeResult.0 ? chargeResult.1 ?? "Charge restore failed" : saved,
                dischargeError: dischargeResult.0 ? nil : dischargeResult.1 ?? "Discharge stop failed"
            )
        }
    }

    private func withTransaction<T>(_ body: () -> T) -> T {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        return body()
    }

    @discardableResult
    private func persist() -> String? {
        let st = fan.status()
        let bat = battery.status()
        let manual: Int
        if case .manual(let targets) = fan.policy {
            manual = targets.sorted(by: { $0.key < $1.key }).first?.value ?? Int(st.fans.first?.targetRPM ?? 2500)
        } else {
            manual = Int(st.fans.first?.targetRPM ?? 2500)
        }
        let result = saveState(PersistedState(
            fanMode: st.desiredMode,
            manualRPM: manual,
            maintain: bat.maintainActive,
            upper: bat.upperLimit,
            lower: bat.lowerLimit,
            chargingEnabled: bat.chargingEnabled,
            forceDischarge: bat.forceDischarge,
            persistEnabled: true
        ).safeForPersistence)
        switch result {
        case .success: persistenceError = nil
        case .failure(let error): persistenceError = "Charge policy could not be saved: \(error.localizedDescription)"
        }
        return persistenceError
    }

    private func restorePersisted() {
        // Boot always starts from hardware-safe transient baselines, even with
        // no state file. The app must explicitly send any forced override.
        _ = fan.restoreSystem()
        _ = battery.setForceDischarge(false)
        guard let s = StateStore.load(), s.persistEnabled else {
            _ = battery.restoreDefaultCharge()
            return
        }
        let restored = s.maintain
            ? battery.setLimit(upper: s.upper, lower: s.lower)
            : battery.setChargingEnabled(s.chargingEnabled)
        guard restored.0 else {
            persistenceError = restored.1 ?? "Saved charge policy could not be restored"
            Logger.state.error("saved policy not applied; retaining saved intent")
            return
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
        reply(withTransaction {
            let bat = battery.status()
            let capabilities = Capabilities(
                fanCount: fan.count, fanControl: fan.canControl, ftstPresent: fan.ftstPresent,
                batteryPresent: bat.present, batteryControl: battery.canControl,
                batteryFamily: battery.family.rawValue, helperVersion: TC.helperVersion,
                protocolVersion: TC.protocolVersion
            )
            let dischargeKey = battery.family == .tahoe ? SMCKey.chIE : SMCKey.ch0I
            capabilities.forceDischargeControl = battery.status().canForceDischarge && smc.keyExists(dischargeKey.rawValue)
            return capabilities
        })
    }

    func getFanStatus(reply: @escaping (FanStatus) -> Void) {
        Task { await watchdog.heartbeat() }
        reply(withTransaction { fan.status() })
    }

    func setFanMode(_ mode: Int, reply: @escaping (Bool, String?) -> Void) {
        guard let mode = FanMode(rawValue: mode), mode != .manual else {
            reply(false, "Invalid fan mode")
            return
        }
        Task { await watchdog.heartbeat() }
        let r = withTransaction {
            fan.setMode(mode)
        }
        reply(r.0, r.1)
    }

    func setFanTargetRPM(_ rpm: Int, fanIndex: Int, reply: @escaping (Bool, String?) -> Void) {
        Task { await watchdog.heartbeat() }
        let r = withTransaction {
            fan.setManual(rpm: rpm, index: fanIndex)
        }
        reply(r.0, r.1)
    }

    func setFanTargets(_ indexes: [NSNumber], rpms: [NSNumber], reply: @escaping (Bool, String?) -> Void) {
        guard indexes.count == rpms.count, !indexes.isEmpty else {
            reply(false, "Invalid fan target")
            return
        }
        var targets: [Int: Int] = [:]
        for (index, rpm) in zip(indexes, rpms) {
            targets[index.intValue] = rpm.intValue
        }
        Task { await watchdog.heartbeat() }
        let r = withTransaction { fan.setManual(targets: targets) }
        reply(r.0, r.1)
    }

    func getBatteryStatus(reply: @escaping (BatteryStatus) -> Void) {
        Task { await watchdog.heartbeat() }
        reply(withTransaction {
            let status = battery.status()
            if let persistenceError {
                status.lastError = [status.lastError, persistenceError].compactMap { $0 }.joined(separator: "; ")
            }
            return status
        })
    }

    func setChargeLimit(_ upper: Int, lower: Int, reply: @escaping (Bool, String?) -> Void) {
        Task { await watchdog.heartbeat() }
        let r: (Bool, String?) = withTransaction {
            guard battery.canControl,
                  (ChargeLimits.minUpper...ChargeLimits.maxPercent).contains(upper),
                  lower >= ChargeLimits.minPercent, lower <= upper - ChargeLimits.minGap else {
                return (false, "Invalid or unsupported charge limits")
            }
            let r = battery.setLimit(upper: upper, lower: lower)
            if r.0, let error = persist() { return (false, error) }
            return r
        }
        reply(r.0, r.1)
    }

    func setChargingEnabled(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        Task { await watchdog.heartbeat() }
        let r: (Bool, String?) = withTransaction {
            guard battery.canControl else { return (false, "Charging control is unsupported") }
            let r = battery.setChargingEnabled(enabled)
            if r.0, let error = persist() { return (false, error) }
            return r
        }
        reply(r.0, r.1)
    }

    func setForceDischarge(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        Task { await watchdog.heartbeat() }
        let r = withTransaction {
            enabled ? battery.setForceDischarge(true) : battery.stopForceDischarge()
        }
        reply(r.0, r.1)
    }

    func restoreSystemControl(reply: @escaping (Bool, String?) -> Void) {
        Task { await watchdog.heartbeat() }
        let result = restoreAll()
        reply(result.0, result.1)
    }

    func restoreComponents(_ components: Int, reply: @escaping (RestoreResult) -> Void) {
        Task { await watchdog.heartbeat() }
        reply(restore(components: components))
    }

    func getThermalSnapshot(reply: @escaping ([TempReading]) -> Void) {
        Task { await watchdog.heartbeat() }
        // ponytail: lock each read so safety writes stay atomic while commands can run between telemetry keys.
        let out = TC.tempKeys.compactMap { key in
            withTransaction {
                smc.readCelsius(key).map { TempReading(key: key, celsius: $0) }
            }
        }
        reply(out)
    }
}