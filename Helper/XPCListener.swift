import Foundation
import os

final class HelperDelegate: NSObject, NSXPCListenerDelegate, ThermalHelperProtocol {
    let smc = SMCService()
    let fan: FanController
    let battery: BatteryController
    let watchdog: SafetyWatchdog
    let power = PowerObserver()
    private let teamIDs: Set<String>
    private let bundles: Set<String> = [TC.appBundleID]

    override init() {
        fan = FanController(smc: smc)
        battery = BatteryController(smc: smc)
        watchdog = SafetyWatchdog(smc: smc, fan: fan, battery: battery)
        teamIDs = HelperDelegate.ownTeams()
        super.init()
        do {
            try smc.open()
            fan.probe()
            battery.probe()
            watchdog.start()
            power.onWake = { [weak self] in self?.watchdog.onWake() }
            power.start()
            restorePersisted()
            let fanN = self.fan.count
            let batFamily = self.battery.family.rawValue
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
        ))
    }

    private func restorePersisted() {
        guard let s = StateStore.load(), s.persistEnabled else { return }
        if let mode = FanMode(rawValue: s.fanMode) {
            if mode == .manual { _ = fan.setManual(rpm: s.manualRPM, index: -1) }
            else { _ = fan.setMode(mode) }
        }
        _ = battery.setForceDischarge(s.forceDischarge)
        if s.maintain {
            _ = battery.setLimit(upper: s.upper, lower: s.lower)
        } else {
            _ = battery.setChargingEnabled(s.chargingEnabled)
        }
        Logger.state.info("restored persisted policy")
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        guard verify(c) else {
            Logger.helper.warning("reject pid=\(c.processIdentifier, privacy: .public) team mismatch or unsigned")
            c.invalidate()
            return false
        }
        c.exportedInterface = ThermalXPC.makeInterface()
        c.exportedObject = self
        c.resume()
        return true
    }

    func ping(_ token: String, reply: @escaping (Bool) -> Void) {
        watchdog.heartbeat(); reply(true)
    }

    func getCapabilities(reply: @escaping (Capabilities) -> Void) {
        watchdog.heartbeat()
        let bat = battery.status()
        reply(Capabilities(
            fanCount: fan.count, fanControl: fan.canControl, ftstPresent: fan.ftstPresent,
            batteryPresent: bat.present, batteryControl: battery.canControl,
            batteryFamily: battery.family.rawValue, helperVersion: TC.helperVersion,
            protocolVersion: TC.protocolVersion
        ))
    }

    func getFanStatus(reply: @escaping (FanStatus) -> Void) { watchdog.heartbeat(); reply(fan.status()) }
    func setFanMode(_ mode: Int, reply: @escaping (Bool, String?) -> Void) {
        watchdog.heartbeat()
        let r = fan.setMode(FanMode(rawValue: mode) ?? .system)
        persist()
        reply(r.0, r.1)
    }
    func setFanTargetRPM(_ rpm: Int, fanIndex: Int, reply: @escaping (Bool, String?) -> Void) {
        watchdog.heartbeat()
        let r = fan.setManual(rpm: rpm, index: fanIndex)
        persist()
        reply(r.0, r.1)
    }
    func getBatteryStatus(reply: @escaping (BatteryStatus) -> Void) { watchdog.heartbeat(); reply(battery.status()) }
    func setChargeLimit(_ upper: Int, lower: Int, reply: @escaping (Bool, String?) -> Void) {
        watchdog.heartbeat()
        let r = battery.setLimit(upper: upper, lower: lower)
        reply(r.0, r.1)
        persist()
    }
    func setChargingEnabled(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        watchdog.heartbeat()
        let r = battery.setChargingEnabled(enabled)
        reply(r.0, r.1)
        persist()
    }
    func setForceDischarge(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        watchdog.heartbeat(); let r = battery.setForceDischarge(enabled); persist(); reply(r.0, r.1)
    }
    func restoreSystemControl(reply: @escaping (Bool, String?) -> Void) {
        watchdog.heartbeat()
        restoreAll()
        reply(true, nil)
    }

    func getThermalSnapshot(reply: @escaping ([TempReading]) -> Void) {
        watchdog.heartbeat()
        var out: [TempReading] = []
        for k in TC.tempKeys {
            if let v = smc.readCelsius(k) {
                out.append(TempReading(key: k, celsius: v))
            }
        }
        reply(out)
    }

    private func verify(_ c: NSXPCConnection) -> Bool {
        var code: SecCode?
        var err = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: c.processIdentifier] as CFDictionary, [], &code)
        guard err == errSecSuccess, let code else { return teamIDs.isEmpty }
        var sc: SecStaticCode?
        err = SecCodeCopyStaticCode(code, [], &sc)
        guard err == errSecSuccess, let sc else { return false }
        var info: CFDictionary?
        err = SecCodeCopySigningInformation(sc, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard err == errSecSuccess, let dict = info as? [String: Any] else { return teamIDs.isEmpty }
        if teamIDs.isEmpty { return true }
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        return team.map { teamIDs.contains($0) } ?? false
    }

    private static func ownTeams() -> Set<String> {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return [] }
        var sc: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &sc) == errSecSuccess, let sc else { return [] }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(sc, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let team = dict[kSecCodeInfoTeamIdentifier as String] as? String else { return [] }
        return [team]
    }
}
