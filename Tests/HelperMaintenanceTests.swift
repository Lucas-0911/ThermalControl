import XCTest
@testable import ThermalControl

@MainActor
final class HelperMaintenanceTests: XCTestCase {
    func testMaintenanceFlagsPreventNormalStartup() {
        for flag in ["--migrate-legacy-helper", "--restore-legacy-control", "--register-helper", "--helper-status", "--set-charge-limit", "--restore-system-control", "--release-transient-control"] {
            XCTAssertTrue(HelperMaintenance.isRequested(["app", flag]))
        }
        XCTAssertFalse(HelperMaintenance.isRequested(["app"]))
    }

    func testChargeLimitArgumentsRejectClampingAndMissingValues() {
        XCTAssertEqual(HelperMaintenance.chargeLimits(in: ["app", "--set-charge-limit", "55", "50"]), ChargeLimits(upper: 55, lower: 50))
        for values in [["55"], ["55", "54"], ["100", "70"], ["80", "19"], ["nan", "70"], ["80", "70", "extra"]] {
            XCTAssertNil(HelperMaintenance.chargeLimits(in: ["app", "--set-charge-limit"] + values))
        }
    }

    func testLegacyRestoreRequiresEveryFanModeAndFullChargeReadback() {
        let capabilities = Capabilities(fanCount: 1, fanControl: true, ftstPresent: false,
            batteryPresent: true, batteryControl: true, batteryFamily: "tahoe", helperVersion: "1.2.2", protocolVersion: 2)
        let fan = FanStatus(fans: [FanChannel(index: 0, actualRPM: 2_000, targetRPM: 2_000,
            minRPM: 1_000, maxRPM: 6_000, modeRaw: 0, modeKey: "F0Md")], desiredMode: 0, ftstPresent: false)
        let battery = BatteryStatus(present: true, percent: 60, externalAC: true, amperageMA: 0,
            voltageMV: 12_000, upperLimit: 100, lowerLimit: 95, chargingEnabled: true,
            maintainActive: false, forceDischarge: false, keyFamily: "tahoe")
        XCTAssertTrue(HelperMaintenance.restored(fan: fan, battery: battery, capabilities: capabilities))
        battery.upperLimit = 55
        battery.lowerLimit = 50
        XCTAssertTrue(HelperMaintenance.restored(fan: fan, battery: battery, capabilities: capabilities), "Legacy restore retains numeric drafts but disables maintain")
        battery.maintainActive = true
        XCTAssertFalse(HelperMaintenance.restored(fan: fan, battery: battery, capabilities: capabilities))
        battery.maintainActive = false
        fan.fans[0].modeRaw = 1
        XCTAssertFalse(HelperMaintenance.restored(fan: fan, battery: battery, capabilities: capabilities))
        XCTAssertFalse(HelperMaintenance.restored(fan: nil, battery: battery, capabilities: capabilities))
    }
}
