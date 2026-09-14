import Foundation
import os

/// 2-second safety loop (Phase 3a modernization: `DispatchSourceTimer` on a
/// serial queue → actor + structured `Task` loop). Timing semantics unchanged:
/// 2s period (`TC.batteryTickInterval`), `TC.heartbeatTimeout` (45s) fallback
/// to System fan, thermal ceiling/hotspot enforcement with `TC.thermalHold`.
///
/// Actor isolation replaces the serial-queue mutual exclusion that previously
/// protected `lastBeat`/`hotSince`/`ticks`.
actor SafetyWatchdog {
    private let smc: any SMCProtocol
    private let fan: any FanControlling
    private let battery: any BatteryControlling
    private var loopTask: Task<Void, Never>?
    private var lastBeat = Date()
    private var hotSince: Date?
    private var ticks = 0

    init(smc: any SMCProtocol, fan: any FanControlling, battery: any BatteryControlling) {
        self.smc = smc
        self.fan = fan
        self.battery = battery
    }

    func start() {
        lastBeat = Date()
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(TC.batteryTickInterval))
                guard let self, !Task.isCancelled else { return }
                await self.tick()
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    func heartbeat() {
        lastBeat = Date()
    }

    /// Re-probe SMC and re-apply policy after sleep/wake (SMC state is lost
    /// across sleep). Previously dispatched onto the watchdog's serial queue.
    func onWake() {
        fan.probe()
        battery.probe()
        _ = fan.apply()
        battery.tick()
    }

    private func tick() {
        ticks += 1
        battery.tick()
        enforceThermal()
        if ticks % 5 == 0, fan.policy != .system { _ = fan.apply() }
        if Date().timeIntervalSince(lastBeat) > TC.heartbeatTimeout, fan.policy != .system {
            Logger.watchdog.notice("heartbeat timeout → System fan")
            _ = fan.restoreSystem()
        }
    }

    private func enforceThermal() {
        guard fan.policy != .system else { hotSince = nil; return }
        let keys = SMCKey.thermalTripKeys
        var hot = 0.0
        var hotspot = false
        for key in keys {
            guard let v = smc.readCelsius(key.rawValue) else { continue }
            if v >= hot {
                hot = v
                hotspot = key.rawValue.hasPrefix("Tp")
            }
        }
        if hot <= 0 {
            // Don't yank fans to Auto just because a tick couldn't decode temps.
            Logger.watchdog.debug("no temp this tick; keep fan policy")
            return
        }
        let cap = hotspot ? TC.thermalHotspotCap : TC.thermalCap
        let limit = min(cap, max(TC.thermalCeiling, hot > TC.thermalCeiling ? cap : TC.thermalCeiling))
        if hot >= TC.thermalCeiling {
            if hotSince == nil { hotSince = Date() }
            if let s = hotSince, Date().timeIntervalSince(s) >= TC.thermalHold, hot >= min(limit, TC.thermalCap) {
                let hotStr = String(format: "%.1f", hot)
                Logger.watchdog.notice("thermal \(hotStr, privacy: .public) → System")
                _ = fan.restoreSystem()
            }
        } else {
            hotSince = nil
        }
    }
}