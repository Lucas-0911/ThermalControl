import XCTest
@testable import ThermalControl

final class SafetyLifecycleTests: XCTestCase {
    func testWatchdogTimeoutRestoresSystemAndDisablesForceDischarge() async {
        let fan = FakeFan()
        let battery = FakeBattery()
        let clock = SafetyClock()
        let watchdog = SafetyWatchdog(smc: FakeSMC(), fan: fan, battery: battery, monotonicNow: { clock.now })
        let persistence = Flag()
        await watchdog.setSafetyFallback { persistence.set() }
        await watchdog.heartbeat()

        clock.now = TC.heartbeatTimeout + 0.1
        await watchdog.checkSafety()

        XCTAssertEqual(fan.policy, .system)
        XCTAssertEqual(fan.restoreCount, 1)
        XCTAssertFalse(battery.forceDischarge)
        XCTAssertTrue(persistence.value)
    }

    func testSleepPausesTickAndRestoresSystemImmediately() async {
        let fan = FakeFan()
        let battery = FakeBattery()
        let watchdog = SafetyWatchdog(smc: FakeSMC(), fan: fan, battery: battery)
        let persistence = Flag()
        await watchdog.setSafetyFallback { persistence.set() }

        await watchdog.onSleep()
        XCTAssertEqual(fan.restoreCount, 1)
        XCTAssertFalse(battery.forceDischarge)
        XCTAssertTrue(persistence.value)

        await watchdog.checkSafety()
        XCTAssertEqual(fan.restoreCount, 1)
        XCTAssertEqual(battery.tickCount, 0)

        await watchdog.onWake()
        XCTAssertEqual(fan.restoreCount, 2)
        XCTAssertEqual(fan.applyCount, 0)
        XCTAssertFalse(battery.forceDischarge)
    }

    func testThermalFreshnessAllowsTwoMissesThenRestoresAtSixSeconds() async {
        let clock = SafetyClock()
        let fan = FakeFan()
        let battery = FakeBattery()
        let smc = FakeSMC()
        let watchdog = SafetyWatchdog(smc: smc, fan: fan, battery: battery, monotonicNow: { clock.now })
        let persistence = Flag()
        await watchdog.setSafetyFallback { persistence.set() }

        clock.now = 2
        await watchdog.checkSafety()
        clock.now = 4
        await watchdog.checkSafety()
        XCTAssertEqual(fan.restoreCount, 0)
        XCTAssertTrue(battery.forceDischarge)
        clock.now = 6
        await watchdog.checkSafety()

        XCTAssertEqual(fan.restoreCount, 1)
        XCTAssertFalse(battery.forceDischarge)
        XCTAssertTrue(persistence.value)
    }

    func testFreshThermalSampleResetsConsecutiveMissingBudget() async {
        let clock = SafetyClock()
        let fan = FakeFan()
        let smc = FakeSMC()
        let watchdog = SafetyWatchdog(smc: smc, fan: fan, battery: FakeBattery(), monotonicNow: { clock.now })
        clock.now = 2
        await watchdog.checkSafety()
        clock.now = 4
        await watchdog.checkSafety()
        smc.temperature = 50
        clock.now = 6
        await watchdog.checkSafety()
        smc.temperature = nil
        clock.now = 8
        await watchdog.checkSafety()
        clock.now = 10
        await watchdog.checkSafety()
        XCTAssertEqual(fan.restoreCount, 0)
        clock.now = 12
        await watchdog.checkSafety()
        XCTAssertEqual(fan.restoreCount, 1)
    }

    func testRampIsCancelledAtThermalCeilingWithoutWaitingForHold() async {
        let fan = FakeFan()
        fan.isRamping = true
        let smc = FakeSMC()
        smc.temperature = TC.thermalCeiling
        let battery = FakeBattery()
        let watchdog = SafetyWatchdog(smc: smc, fan: fan, battery: battery)
        await watchdog.checkSafety()
        XCTAssertEqual(fan.policy, .system)
        XCTAssertEqual(fan.restoreCount, 1)
        XCTAssertFalse(battery.forceDischarge)
    }

    func testThermalTripPreservesHundredForEightSecondsThenHundredFiveRule() async {
        let clock = SafetyClock()
        let fan = FakeFan()
        let battery = FakeBattery()
        let smc = FakeSMC()
        smc.temperature = 100
        let watchdog = SafetyWatchdog(smc: smc, fan: fan, battery: battery, monotonicNow: { clock.now })
        await watchdog.checkSafety()
        smc.temperature = 105
        clock.now = 7.99
        await watchdog.checkSafety()
        XCTAssertEqual(fan.restoreCount, 0)
        smc.temperature = 104
        clock.now = 8
        await watchdog.checkSafety()
        XCTAssertEqual(fan.restoreCount, 0)
        smc.temperature = 105
        await watchdog.checkSafety()
        XCTAssertEqual(fan.restoreCount, 1)
        XCTAssertFalse(battery.forceDischarge)
    }

    func testBelowHundredResetsThermalHold() async {
        let clock = SafetyClock()
        let fan = FakeFan()
        let smc = FakeSMC()
        smc.temperature = 105
        let watchdog = SafetyWatchdog(smc: smc, fan: fan, battery: FakeBattery(), monotonicNow: { clock.now })
        await watchdog.checkSafety()
        clock.now = 7
        smc.temperature = 99
        await watchdog.checkSafety()
        clock.now = 8
        smc.temperature = 105
        await watchdog.heartbeat()
        await watchdog.checkSafety()
        clock.now = 15.99
        await watchdog.checkSafety()
        XCTAssertEqual(fan.restoreCount, 0)
        clock.now = 16
        await watchdog.checkSafety()
        XCTAssertEqual(fan.restoreCount, 1)
    }

    func testMissingTelemetryAlsoStopsDischargeWithSystemFans() async {
        let clock = SafetyClock()
        let fan = FakeFan()
        fan.policy = .system
        let battery = FakeBattery()
        let watchdog = SafetyWatchdog(smc: FakeSMC(), fan: fan, battery: battery, monotonicNow: { clock.now })
        for time in [2.0, 4, 6] {
            clock.now = time
            await watchdog.checkSafety()
        }
        XCTAssertFalse(battery.forceDischarge)
        XCTAssertEqual(fan.restoreCount, 1)
    }

    func testMissingTelemetryRejectsNaNAndInfiniteReadings() async {
        for temperature in [Double.nan, Double.infinity, 0, -1] {
            let clock = SafetyClock()
            let fan = FakeFan()
            let smc = FakeSMC()
            smc.temperature = temperature
            let watchdog = SafetyWatchdog(smc: smc, fan: fan, battery: FakeBattery(), monotonicNow: { clock.now })
            for time in [2.0, 4, 6] {
                clock.now = time
                await watchdog.checkSafety()
            }
            XCTAssertEqual(fan.restoreCount, 1)
        }
    }

    func testSleepWakeResetsThermalHoldAndFreshnessBudget() async {
        let clock = SafetyClock()
        let fan = FakeFan()
        let smc = FakeSMC()
        smc.temperature = 105
        let watchdog = SafetyWatchdog(smc: smc, fan: fan, battery: FakeBattery(), monotonicNow: { clock.now })
        await watchdog.checkSafety()
        clock.now = 7
        await watchdog.onSleep()
        clock.now = 100
        await watchdog.onWake()
        fan.policy = .max
        await watchdog.checkSafety()
        XCTAssertEqual(fan.restoreCount, 2)
        clock.now = 108
        await watchdog.checkSafety()
        XCTAssertEqual(fan.restoreCount, 3)
    }

    func testProtocolDefaultStopIsExplicitFailure() {
        let result = FakeBattery().stopForceDischarge()
        XCTAssertFalse(result.0)
        XCTAssertNotNil(result.1)
    }

    func testXPCReplyCancellationBeforeContinuationInstall() async {
        let reply = XPCReply<String?>()
        reply.resume(nil)
        let value: String? = await withCheckedContinuation { reply.install($0) }
        XCTAssertNil(value)
        XCTAssertTrue(reply.isFinished)
        reply.resume("late")
    }

    func testXPCReplyCleanupRunsOnce() async {
        let flag = Flag()
        let value: String = await withCheckedContinuation { continuation in
            let reply = XPCReply(continuation)
            reply.onFinish { flag.set() }
            reply.resume("cancelled")
            reply.resume("late")
        }
        XCTAssertEqual(value, "cancelled")
        XCTAssertTrue(flag.value)
    }

    func testXPCReplyTimeoutAndLateCompletionResumeOnlyOnce() async {
        let value: String = await withCheckedContinuation { continuation in
            let reply = XPCReply(continuation)
            reply.resume("timeout")
            reply.resume("late reply")
        }
        XCTAssertEqual(value, "timeout")
    }
}

private final class SafetyClock {
    var now: TimeInterval = 0
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool { lock.withLock { stored } }
    func set() { lock.withLock { stored = true } }
}

private final class FakeFan: FanControlling {
    var count = 1
    var canControl = true
    var ftstPresent = false
    var policy: FanPolicy = .max
    var isRamping = false
    var restoreCount = 0
    var applyCount = 0
    func probe() {}
    func status() -> FanStatus { FanStatus(fans: [], desiredMode: FanMode.max.rawValue, ftstPresent: false) }
    func setMode(_ mode: FanMode) -> (Bool, String?) { policy = mode == .system ? .system : .max; return (true, nil) }
    func setManual(rpm: Int, index: Int) -> (Bool, String?) { (true, nil) }
    func restoreSystem() -> (Bool, String?) { policy = .system; restoreCount += 1; return (true, nil) }
    func apply() -> (Bool, String?) { applyCount += 1; return (true, nil) }
}

private final class FakeBattery: BatteryControlling {
    var canControl = true
    var family: BatteryFamily = .tahoe
    var forceDischarge = true
    var tickCount = 0
    func probe() {}
    func status() -> BatteryStatus {
        BatteryStatus(present: true, percent: 50, externalAC: true, amperageMA: 0, voltageMV: 0,
                      upperLimit: 80, lowerLimit: 70, chargingEnabled: true, maintainActive: true,
                      forceDischarge: forceDischarge, keyFamily: family.rawValue)
    }
    func setLimit(upper: Int, lower: Int) -> (Bool, String?) { (true, nil) }
    func setChargingEnabled(_ enabled: Bool) -> (Bool, String?) { (true, nil) }
    func setForceDischarge(_ enabled: Bool) -> (Bool, String?) { forceDischarge = enabled; return (true, nil) }
    func disableForceDischarge() { forceDischarge = false }
    func restoreDefaultCharge() -> (Bool, String?) { (true, nil) }
    func tick() { tickCount += 1 }
}

private final class FakeSMC: SMCProtocol {
    var temperature: Double?
    func open() throws {}
    func close() {}
    func keyExists(_ key: String) -> Bool { false }
    func info(_ key: String) throws -> SMCKeyInfo { throw CocoaError(.fileReadUnknown) }
    func readBytes(_ key: String) throws -> (SMCKeyInfo, [UInt8]) { throw CocoaError(.fileReadUnknown) }
    func readUInt8(_ key: String) throws -> UInt8 { 0 }
    func readDouble(_ key: String) throws -> Double { 0 }
    func readCelsius(_ key: String) -> Double? { temperature }
    func writeUInt8(_ key: String, _ value: UInt8, verify: Bool) throws {}
    func writeDouble(_ key: String, _ value: Double, verify: Bool) throws {}
    func writeBytesDirect(_ key: String, size: UInt32, _ bytes: [UInt8]) throws {}
    func writeBytes(_ key: String, _ bytes: [UInt8], verify: Bool) throws {}
}
