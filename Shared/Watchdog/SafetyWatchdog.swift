import Foundation
import os
#if TESTING
@testable import ThermalControl
#endif

/// Safety loop: enforces thermal policy and restores safe hardware state when
/// heartbeat expires or system sleeps.
actor SafetyWatchdog {
    private let smc: any SMCProtocol
    private let fan: any FanControlling
    private let battery: any BatteryControlling
    private let transactionLock: NSRecursiveLock
    private var loopTask: Task<Void, Never>?
    private let monotonicNow: () -> TimeInterval
    private var lastBeat: TimeInterval
    private var hotSince: TimeInterval?
    private var lastThermalSample: TimeInterval
    private var missingThermalSamples = 0
    private var heartbeatTimedOut = false
    private var sleeping = false
    private var safetyFallback: (@Sendable () -> Void)?
    private var ticks = 0

    init(
        smc: any SMCProtocol,
        fan: any FanControlling,
        battery: any BatteryControlling,
        transactionLock: NSRecursiveLock = NSRecursiveLock(),
        monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.smc = smc
        self.fan = fan
        self.battery = battery
        self.transactionLock = transactionLock
        self.monotonicNow = monotonicNow
        self.lastBeat = monotonicNow()
        self.lastThermalSample = self.lastBeat
    }

    func start() {
        lastBeat = monotonicNow()
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

    func setSafetyFallback(_ action: @escaping @Sendable () -> Void) {
        safetyFallback = action
    }

    func heartbeat() {
        lastBeat = monotonicNow()
        heartbeatTimedOut = false
    }

    func onSleep() {
        sleeping = true
        hotSince = nil
        missingThermalSamples = 0
        withTransaction {
            _ = fan.restoreSystem()
            battery.disableForceDischarge()
            safetyFallback?()
        }
    }

    /// SMC state is lost across sleep. Re-probe it, but keep transient fan and
    /// discharge overrides disabled until the app reconnects and commands them.
    func onWake() {
        sleeping = false
        hotSince = nil
        lastThermalSample = monotonicNow()
        missingThermalSamples = 0
        withTransaction {
            fan.probe()
            battery.probe()
            _ = fan.restoreSystem()
            battery.disableForceDischarge()
            safetyFallback?()
        }
        lastBeat = monotonicNow()
        heartbeatTimedOut = false
    }

    /// Test seam: evaluates lifecycle safety immediately without waiting for
    /// the production timer interval.
    func checkSafety() {
        tick()
    }

    private func tick() {
        guard !sleeping else { return }
        let now = monotonicNow()
        withTransaction {
            ticks += 1
            battery.tick()
            enforceThermal(now: now)
            if ticks % 5 == 0, fan.policy != .system { _ = fan.apply() }
            if now - lastBeat > TC.heartbeatTimeout, !heartbeatTimedOut {
                heartbeatTimedOut = true
                Logger.watchdog.fault("heartbeat timeout → System fan, force discharge off")
                _ = fan.restoreSystem()
                battery.disableForceDischarge()
                safetyFallback?()
            }
        }
    }

    private func withTransaction<T>(_ body: () -> T) -> T {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        return body()
    }

    private func enforceThermal(now: TimeInterval) {
        guard fan.policy != .system || battery.status().forceDischarge else {
            hotSince = nil
            lastThermalSample = now
            missingThermalSamples = 0
            return
        }
        let hot = SMCKey.thermalTripKeys.compactMap { smc.readCelsius($0.rawValue) }
            .filter { $0.isFinite && $0 > 0 }.max()
        guard let hot else {
            missingThermalSamples += 1
            // Technical freshness budget, not a thermal limit: 3 failed 2-second ticks / 6 seconds.
            if missingThermalSamples >= 3, now - lastThermalSample >= 3 * TC.batteryTickInterval {
                Logger.watchdog.fault("thermal telemetry stale → System fan, force discharge off")
                _ = fan.restoreSystem()
                battery.disableForceDischarge()
                safetyFallback?()
            }
            return
        }
        lastThermalSample = now
        missingThermalSamples = 0
        if hot >= TC.thermalCeiling {
            if fan.isRamping {
                _ = fan.restoreSystem()
                battery.disableForceDischarge()
                safetyFallback?()
                hotSince = nil
                return
            }
            if hotSince == nil { hotSince = now }
            if let since = hotSince, now - since >= TC.thermalHold, hot >= TC.thermalCap {
                let hotStr = String(format: "%.1f", hot)
                Logger.watchdog.notice("thermal \(hotStr, privacy: .public) → System")
                _ = fan.restoreSystem()
                battery.disableForceDischarge()
                safetyFallback?()
            }
        } else {
            hotSince = nil
        }
    }
}