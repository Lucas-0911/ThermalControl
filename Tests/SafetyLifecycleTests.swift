import XCTest
@testable import ThermalControl

final class SafetyLifecycleTests: XCTestCase {
    func testWatchdogTimeoutRestoresSystemAndDisablesForceDischarge() async {
        let fan = FakeFan()
        let battery = FakeBattery()
        let watchdog = SafetyWatchdog(smc: FakeSMC(), fan: fan, battery: battery)
        let persistence = Flag()
        await watchdog.setSafetyFallback { persistence.set() }
        await watchdog.heartbeat()

        await watchdog.checkSafety(now: Date().addingTimeInterval(TC.heartbeatTimeout + 0.1))

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

        await watchdog.checkSafety(now: Date().addingTimeInterval(TC.heartbeatTimeout + 1))
        XCTAssertEqual(fan.restoreCount, 1)
        XCTAssertEqual(battery.tickCount, 0)

        await watchdog.onWake()
        XCTAssertEqual(fan.restoreCount, 2)
        XCTAssertEqual(fan.applyCount, 0)
        XCTAssertFalse(battery.forceDischarge)
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
    func restoreDefaultCharge() {}
    func tick() { tickCount += 1 }
}

private final class FakeSMC: SMCProtocol {
    func open() throws {}
    func close() {}
    func keyExists(_ key: String) -> Bool { false }
    func info(_ key: String) throws -> SMCKeyInfo { throw CocoaError(.fileReadUnknown) }
    func readBytes(_ key: String) throws -> (SMCKeyInfo, [UInt8]) { throw CocoaError(.fileReadUnknown) }
    func readUInt8(_ key: String) throws -> UInt8 { 0 }
    func readDouble(_ key: String) throws -> Double { 0 }
    func readCelsius(_ key: String) -> Double? { nil }
    func writeUInt8(_ key: String, _ value: UInt8, verify: Bool) throws {}
    func writeDouble(_ key: String, _ value: Double, verify: Bool) throws {}
    func writeBytesDirect(_ key: String, size: UInt32, _ bytes: [UInt8]) throws {}
    func writeBytes(_ key: String, _ bytes: [UInt8], verify: Bool) throws {}
}
