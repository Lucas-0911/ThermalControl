import XCTest

final class HelperXPCServiceTests: XCTestCase {
    func testRestoreReturnsPartialFailureAndStillRestoresBattery() {
        let smc = ControllerTestSMC()
        let fan = FanController(smc: smc)
        fan.probe()
        smc.failKey = "F0Md"
        let battery = RestoreTestBattery()
        let lock = NSRecursiveLock()
        let watchdog = SafetyWatchdog(smc: smc, fan: fan, battery: battery, transactionLock: lock)
        let service = HelperXPCService(smc: smc, fan: fan, battery: battery, watchdog: watchdog,
                                       transactionLock: lock, saveState: { _ in .success(()) })

        service.restoreSystemControl { ok, error in
            XCTAssertFalse(ok)
            XCTAssertNotNil(error)
        }
        XCTAssertEqual(battery.restoreCount, 1)
        XCTAssertEqual(smc.writes, ["F0Md", "F1Md"])
    }

    func testTransientFanCommandsNeverSaveChargePolicy() {
        let smc = ControllerTestSMC()
        let fan = FanController(smc: smc)
        fan.probe()
        let battery = RestoreTestBattery()
        let lock = NSRecursiveLock()
        var saves = 0
        let service = HelperXPCService(
            smc: smc, fan: fan, battery: battery,
            watchdog: SafetyWatchdog(smc: smc, fan: fan, battery: battery, transactionLock: lock),
            transactionLock: lock, saveState: { _ in saves += 1; return .success(()) }
        )
        service.setFanMode(FanMode.system.rawValue) { ok, _ in XCTAssertTrue(ok) }
        service.restoreComponents(RestoreResult.fan) { result in XCTAssertTrue(result.succeeded) }
        XCTAssertEqual(saves, 0)
    }

    func testInvalidModeDoesNotBecomeSuccessfulSystemRestore() {
        let smc = ControllerTestSMC()
        let fan = FanController(smc: smc)
        fan.probe()
        let battery = RestoreTestBattery()
        let lock = NSRecursiveLock()
        let service = HelperXPCService(smc: smc, fan: fan, battery: battery,
                                       watchdog: SafetyWatchdog(smc: smc, fan: fan, battery: battery, transactionLock: lock),
                                       transactionLock: lock, saveState: { _ in .success(()) })
        service.setFanMode(Int.max) { ok, error in
            XCTAssertFalse(ok)
            XCTAssertNotNil(error)
        }
        XCTAssertTrue(smc.writes.isEmpty)
    }
}

private final class RestoreTestBattery: BatteryControlling {
    var canControl = true
    var family: BatteryFamily = .tahoe
    var restoreCount = 0
    func probe() {}
    func status() -> BatteryStatus {
        BatteryStatus(present: true, percent: 50, externalAC: true, amperageMA: 0, voltageMV: 12_000,
                      upperLimit: 80, lowerLimit: 70, chargingEnabled: true, maintainActive: false,
                      forceDischarge: false, keyFamily: family.rawValue)
    }
    func setLimit(upper: Int, lower: Int) -> (Bool, String?) { (true, nil) }
    func setChargingEnabled(_ enabled: Bool) -> (Bool, String?) { (true, nil) }
    func setForceDischarge(_ enabled: Bool) -> (Bool, String?) { (true, nil) }
    func disableForceDischarge() {}
    func restoreDefaultCharge() -> (Bool, String?) { restoreCount += 1; return (true, nil) }
    func tick() {}
}
