import XCTest
@testable import ThermalControl

/// Protects the hardware-threshold constants that must never be re-tuned as a
/// side effect of refactoring (reverse-engineered values).
final class ConstantsTests: XCTestCase {
    func testTempKeySetIsStable() {
        // Canonical list (was 23 entries after centralization).
        XCTAssertEqual(TC.tempKeys.count, 23)
        XCTAssertEqual(Set(TC.tempKeys).count, TC.tempKeys.count, "duplicate temp keys")
    }

    func testThermalThresholds() {
        XCTAssertEqual(TC.thermalCeiling, 100)
        XCTAssertEqual(TC.thermalCap, 105)
        XCTAssertEqual(TC.thermalHotspotCap, 110)
        XCTAssertEqual(TC.thermalHold, 8)
    }

    func testTimingConstants() {
        XCTAssertEqual(TC.heartbeatInterval, 5)
        XCTAssertEqual(TC.heartbeatTimeout, 45)
        XCTAssertEqual(TC.uiPollInterval, 3)
        XCTAssertEqual(TC.batteryTickInterval, 2)
    }

    func testFanTimingConstants() {
        XCTAssertEqual(TC.ftstYield, 0.4)
        XCTAssertEqual(TC.modeRetry, 12)
        XCTAssertEqual(TC.modeRetrySleep, 0.05)
        XCTAssertEqual(TC.writeSettle, 0.25)
    }

    func testChargeConstants() {
        XCTAssertEqual(TC.chargeTruthMA, 20)
        XCTAssertEqual(TC.chargeInhibitByteHigh, 0x02)
        XCTAssertEqual(TC.chargeInhibitByteLow, 0x01)
    }

    func testProtocolVersionStable() {
        XCTAssertEqual(TC.protocolVersion, 2)
        XCTAssertEqual(TC.helperVersion, "1.2.2")
        XCTAssertEqual(TC.appBundleID, "com.thermalcontrol.app")
        XCTAssertEqual(TC.helperBundleID, "com.thermalcontrol.helper")
    }
}