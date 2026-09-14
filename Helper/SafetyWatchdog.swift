import Foundation
import os

final class SafetyWatchdog {
    private let smc: any SMCProtocol
    private let fan: FanController
    private let battery: BatteryController
    private let queue = DispatchQueue(label: "com.thermalcontrol.watchdog")
    private var timer: DispatchSourceTimer?
    private var lastBeat = Date()
    private var hotSince: Date?
    private var ticks = 0

    init(smc: any SMCProtocol, fan: FanController, battery: BatteryController) {
        self.smc = smc
        self.fan = fan
        self.battery = battery
    }

    func start() {
        lastBeat = Date()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 2)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func heartbeat() { queue.async { self.lastBeat = Date() } }

    func onWake() {
        queue.async {
            self.fan.probe()
            self.battery.probe()
            _ = self.fan.apply()
            self.battery.tick()
        }
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
