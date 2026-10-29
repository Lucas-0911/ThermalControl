import XCTest
import IOKit.ps

final class BatteryControllerTests: XCTestCase {
    func testStopAlwaysWritesAndVerifiesInsteadOfTrustingCachedFalse() {
        let smc = FakeBatterySMC(keys: [SMCKey.chIE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { (true, 50, true) })
        controller.probe()

        XCTAssertTrue(controller.stopForceDischarge().0)
        smc.values[SMCKey.chIE.rawValue] = 1 // Hardware changed after cached Off.
        XCTAssertTrue(controller.stopForceDischarge().0)

        XCTAssertEqual(smc.writes, [.u8(SMCKey.chIE.rawValue, 0), .u8(SMCKey.chIE.rawValue, 0)])
        XCTAssertEqual(smc.reads, [SMCKey.chIE.rawValue, SMCKey.chIE.rawValue])
        XCTAssertFalse(controller.forceDischarge)
        XCTAssertTrue(controller.status().dischargeStopVerified)
    }

    func testCHIEOnlyCannotControlChargeOrStartDischarge() {
        let smc = FakeBatterySMC(keys: [SMCKey.chIE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { (true, 90, true) })
        controller.probe()

        XCTAssertFalse(controller.canControl)
        XCTAssertFalse(controller.status().canControlCharge)
        XCTAssertFalse(controller.status().canForceDischarge)
        XCTAssertFalse(controller.setLimit(upper: 80, lower: 70).0)
        XCTAssertFalse(controller.setChargingEnabled(false).0)
        XCTAssertFalse(controller.setChargingEnabled(true).0)
        XCTAssertFalse(controller.setForceDischarge(true).0)
        XCTAssertTrue(smc.writes.isEmpty)
        XCTAssertTrue(controller.restoreDefaultCharge().0)
        XCTAssertEqual(smc.writes, [.u8(SMCKey.chIE.rawValue, 0)])
    }

    func testFailedForceDischargeWriteRunsVerifiedStop() {
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue, SMCKey.chIE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { (true, 90, true) })
        controller.probe()
        XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
        smc.failOnValue = 1

        let result = controller.setForceDischarge(true)

        XCTAssertFalse(result.0)
        XCTAssertFalse(controller.forceDischarge)
        XCTAssertTrue(controller.status().dischargeStopVerified)
        XCTAssertEqual(smc.values[SMCKey.chIE.rawValue], 0)
    }

    func testFailedLimitWriteRollsBackLogicalState() {
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue], failDirectWrite: true)
        let controller = BatteryController(smc: smc, batteryReader: { (true, 50, true) })
        controller.probe()

        let result = controller.setLimit(upper: 85, lower: 70)

        XCTAssertFalse(result.0)
        XCTAssertEqual(controller.upper, 80)
        XCTAssertEqual(controller.lower, 70)
        XCTAssertFalse(controller.maintainActive)
        XCTAssertTrue(controller.chargingEnabled)
    }

    func testHysteresisDoesNotRepeatKnownGateWrite() {
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { (true, 85, true) })
        controller.probe()
        XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
        smc.writes.removeAll()
        controller.suppressTick(seconds: 0)

        controller.tick()

        XCTAssertTrue(smc.writes.isEmpty)
        XCTAssertFalse(controller.chargingEnabled)
    }

    func testProbeInvalidatesKnownGateStateAfterWake() {
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { (true, 85, true) })
        controller.probe()
        XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
        smc.writes.removeAll()

        controller.probe()
        controller.suppressTick(seconds: 0)
        controller.tick()

        XCTAssertEqual(smc.writes, [.bytes(SMCKey.chTE.rawValue, 4, [1, 0, 0, 0])])
    }

    func testForceDischargeInvalidatesKnownChargeGateState() {
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue, SMCKey.chIE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { (true, 85, true) })
        controller.probe()
        XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
        XCTAssertTrue(controller.setForceDischarge(true).0)
        XCTAssertTrue(controller.setForceDischarge(false).0)
        smc.writes.removeAll()

        controller.suppressTick(seconds: 0)
        controller.tick()

        XCTAssertEqual(smc.writes, [.bytes(SMCKey.chTE.rawValue, 4, [1, 0, 0, 0])])
    }

    func testRestoreReportsGateFailure() {
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue], failDirectWrite: true)
        let controller = BatteryController(smc: smc)
        controller.probe()
        let result = controller.restoreDefaultCharge()
        XCTAssertFalse(result.0)
        XCTAssertNotNil(result.1)
    }

    func testRestoreWithoutDischargeKeyStillEnablesCharging() {
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue])
        let controller = BatteryController(smc: smc)
        controller.probe()
        let result = controller.restoreDefaultCharge()
        XCTAssertTrue(result.0)
        XCTAssertEqual(smc.writes, [.bytes(SMCKey.chTE.rawValue, 4, [0, 0, 0, 0])])
    }

    func testRestoreWithoutBatteryControlIsNotApplicable() {
        let controller = BatteryController(smc: FakeBatterySMC(keys: []))
        controller.probe()
        XCTAssertTrue(controller.restoreDefaultCharge().0)
    }

    func testDischargeRequiresMaintainACAndTrustedPercentAboveUpper() {
        for io in [(true, 80, true), (true, 79, true), (true, 90, false), (false, 90, true), (true, 101, true)] {
            let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue, SMCKey.chIE.rawValue])
            var snapshot = (present: true, percent: 90, ac: true)
            let controller = BatteryController(smc: smc, batteryReader: { snapshot })
            controller.probe()
            XCTAssertFalse(controller.setForceDischarge(true).0)
            XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
            smc.writes.removeAll()
            snapshot = io
            XCTAssertFalse(controller.setForceDischarge(true).0)
            XCTAssertTrue(smc.writes.isEmpty)
        }
    }

    func testActiveDischargeLocksChargeCommandsAndDoesNotExtendDeadline() {
        let clock = BatteryClock()
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue, SMCKey.chIE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { (true, 90, true) }, monotonicNow: { clock.now })
        controller.probe()
        XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
        XCTAssertTrue(controller.setForceDischarge(true).0)
        XCTAssertEqual(controller.status().dischargeTargetPercent, 80)
        XCTAssertEqual(controller.status().dischargeRemainingSeconds, 3600)
        smc.writes.removeAll()

        clock.now = 100
        XCTAssertTrue(controller.setForceDischarge(true).0)
        XCTAssertEqual(controller.status().dischargeRemainingSeconds, 3500)
        XCTAssertFalse(controller.setLimit(upper: 90, lower: 80).0)
        XCTAssertFalse(controller.setChargingEnabled(true).0)
        XCTAssertFalse(controller.setChargingEnabled(false).0)
        XCTAssertEqual(controller.status().dischargeTargetPercent, 80)
        XCTAssertTrue(smc.writes.isEmpty)

        clock.now = 3600
        controller.tick()
        XCTAssertFalse(controller.forceDischarge)
        XCTAssertTrue(controller.status().dischargeStopVerified)
        XCTAssertEqual(controller.status().dischargeStopReason, "deadline")
    }

    func testDischargeStopsAtTargetUnplugAndUntrustedIOEvenDuringSuppression() {
        let cases: [((Bool, Int, Bool), String)] = [
            ((true, 80, true), "targetReached"),
            ((true, 79, true), "targetReached"),
            ((true, 90, false), "unplugged"),
            ((false, 90, true), "untrustedIO"),
            ((true, -1, true), "untrustedIO"),
        ]
        for (snapshot, reason) in cases {
            var io = (present: true, percent: 90, ac: true)
            let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue, SMCKey.chIE.rawValue])
            let controller = BatteryController(smc: smc, batteryReader: { io })
            controller.probe()
            XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
            XCTAssertTrue(controller.setForceDischarge(true).0)
            controller.suppressTick(seconds: 100)
            smc.writes.removeAll()

            io = snapshot
            controller.tick()

            XCTAssertFalse(controller.forceDischarge)
            XCTAssertTrue(controller.status().dischargeStopVerified)
            XCTAssertEqual(controller.status().dischargeStopReason, reason)
            XCTAssertEqual(controller.status().dischargeTargetPercent, -1)
            if reason == "untrustedIO" {
                XCTAssertFalse(controller.maintainActive)
                XCTAssertEqual(smc.writes, [.u8(SMCKey.chIE.rawValue, 0),
                                            .bytes(SMCKey.chTE.rawValue, 4, [0, 0, 0, 0]), .u8(SMCKey.chIE.rawValue, 0)])
            } else {
                XCTAssertEqual(smc.writes, [.u8(SMCKey.chIE.rawValue, 0)])
            }
        }
    }

    func testFailedStopPreservesActiveStateBlocksRestoreAndRetriesOnTick() {
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue, SMCKey.chIE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { (true, 90, true) })
        controller.probe()
        XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
        XCTAssertTrue(controller.setForceDischarge(true).0)
        smc.failUInt8Write = true
        smc.writes.removeAll()

        XCTAssertFalse(controller.stopForceDischarge().0)
        XCTAssertTrue(controller.forceDischarge)
        XCTAssertFalse(controller.status().dischargeStopVerified)
        XCTAssertFalse(controller.restoreDefaultCharge().0)
        XCTAssertFalse(controller.setChargingEnabled(true).0)
        XCTAssertFalse(controller.setLimit(upper: 90, lower: 80).0)
        XCTAssertFalse(controller.setForceDischarge(true).0)
        XCTAssertTrue(smc.writes.isEmpty)

        smc.failUInt8Write = false
        controller.tick()
        XCTAssertFalse(controller.forceDischarge)
        XCTAssertTrue(controller.status().dischargeStopVerified)
        XCTAssertEqual(smc.writes, [.u8(SMCKey.chIE.rawValue, 0)])
    }

    func testStopReadbackMismatchOrReadFailureNeverClaimsVerifiedOff() {
        for failRead in [false, true] {
            let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue, SMCKey.chIE.rawValue])
            let controller = BatteryController(smc: smc, batteryReader: { (true, 90, true) })
            controller.probe()
            XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
            XCTAssertTrue(controller.setForceDischarge(true).0)
            smc.ignoreOffWrite = true
            smc.failRead = failRead

            XCTAssertFalse(controller.stopForceDischarge().0)
            XCTAssertTrue(controller.forceDischarge)
            XCTAssertFalse(controller.status().dischargeStopVerified)
            XCTAssertNotNil(controller.status().lastError)
        }
    }

    func testUntrustedIORestoresDefaultOnceInsteadOfRunningHysteresis() {
        var io = (present: true, percent: 90, ac: true)
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { io })
        controller.probe()
        XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
        controller.suppressTick(seconds: 100)
        smc.writes.removeAll()

        io = (false, 0, false)
        controller.tick()
        XCTAssertEqual(smc.writes, [.bytes(SMCKey.chTE.rawValue, 4, [0, 0, 0, 0])])
        XCTAssertTrue(controller.chargingEnabled)
        XCTAssertFalse(controller.maintainActive)
        XCTAssertNotNil(controller.lastError)
        smc.writes.removeAll()
        controller.tick()
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testUntrustedIORestoreFailureRetainsPolicyAndRetries() {
        var io = (present: true, percent: 90, ac: true)
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { io })
        controller.probe()
        XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
        smc.failDirectWrite = true
        io = (false, 0, false)
        controller.tick()
        XCTAssertTrue(controller.maintainActive)
        XCTAssertFalse(controller.chargingEnabled)
        XCTAssertNotNil(controller.lastError)

        smc.failDirectWrite = false
        smc.writes.removeAll()
        controller.tick()
        XCTAssertFalse(controller.maintainActive)
        XCTAssertTrue(controller.chargingEnabled)
        XCTAssertEqual(smc.writes, [.bytes(SMCKey.chTE.rawValue, 4, [0, 0, 0, 0])])
    }

    func testProbeInvalidatesSessionAndTickStopsInsteadOfResuming() {
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue, SMCKey.chIE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { (true, 90, true) })
        controller.probe()
        XCTAssertTrue(controller.setLimit(upper: 80, lower: 70).0)
        XCTAssertTrue(controller.setForceDischarge(true).0)
        controller.probe()
        controller.suppressTick(seconds: 100)

        controller.tick()

        XCTAssertFalse(controller.forceDischarge)
        XCTAssertTrue(controller.status().dischargeStopVerified)
        XCTAssertEqual(controller.status().dischargeStopReason, "sessionMissing")
        XCTAssertEqual(controller.status().dischargeTargetPercent, -1)
    }

    func testBatteryStatusSecureCodingRoundTripPreservesSessionSafety() throws {
        let status = BatteryStatus(present: true, percent: 90, externalAC: true, amperageMA: 0, voltageMV: 0,
                                   upperLimit: 80, lowerLimit: 70, chargingEnabled: false, maintainActive: true,
                                   forceDischarge: true, keyFamily: "tahoe", canControlCharge: true,
                                   canForceDischarge: true, dischargeTargetPercent: 80, dischargeRemainingSeconds: 42,
                                   dischargeStopVerified: false, dischargeStopReason: "deadline")
        let data = try NSKeyedArchiver.archivedData(withRootObject: status, requiringSecureCoding: true)
        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: BatteryStatus.self, from: data))
        XCTAssertTrue(decoded.canControlCharge)
        XCTAssertTrue(decoded.canForceDischarge)
        XCTAssertEqual(decoded.dischargeTargetPercent, 80)
        XCTAssertEqual(decoded.dischargeRemainingSeconds, 42)
        XCTAssertFalse(decoded.dischargeStopVerified)
        XCTAssertEqual(decoded.dischargeStopReason, "deadline")
    }

    func testBatteryParserRejectsMissingOrInvalidFieldsButKeepsRealZero() {
        let invalidDescriptions: [[String: Any]] = [
            [:],
            [kIOPSCurrentCapacityKey: 90],
            [kIOPSPowerSourceStateKey: kIOPSACPowerValue],
            [kIOPSCurrentCapacityKey: -1, kIOPSPowerSourceStateKey: kIOPSACPowerValue],
            [kIOPSCurrentCapacityKey: 101, kIOPSPowerSourceStateKey: kIOPSACPowerValue],
            [kIOPSCurrentCapacityKey: 90, kIOPSPowerSourceStateKey: "Unknown"],
        ]
        for description in invalidDescriptions {
            XCTAssertFalse(SensorReads.batteryIO(description: description).present)
        }
        let zero = SensorReads.batteryIO(description: [kIOPSCurrentCapacityKey: 0, kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue])
        XCTAssertTrue(zero.present)
        XCTAssertEqual(zero.percent, 0)
        XCTAssertFalse(zero.ac)
    }

    func testStateStoreAtomicSaveSanitizesSessionAndReportsFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("state.json")
        let state = PersistedState(fanMode: 0, manualRPM: 0, maintain: true, upper: 80, lower: 70,
                                   chargingEnabled: false, forceDischarge: true, persistEnabled: true)
        try StateStore.save(state, to: destination).get()
        let saved = try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: destination))
        XCTAssertFalse(saved.forceDischarge)
        XCTAssertEqual(saved.upper, 80)

        let invalidDestination = destination.appendingPathComponent("state.json")
        switch StateStore.save(state, to: invalidDestination) {
        case .success: XCTFail("Saving below a regular file must fail")
        case .failure: break
        }
        XCTAssertEqual(try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: destination)), saved)
    }

    func testTahoeInhibitPayloadStaysBigEndian() {
        let smc = FakeBatterySMC(keys: [SMCKey.chTE.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { (true, 80, true) })
        controller.probe()

        XCTAssertTrue(controller.setChargingEnabled(false).0)

        XCTAssertEqual(smc.writes, [.bytes(SMCKey.chTE.rawValue, 4, [1, 0, 0, 0])])
    }

    func testLegacyInhibitWritesHighByteInKeyOrder() {
        let smc = FakeBatterySMC(keys: [SMCKey.ch0B.rawValue, SMCKey.ch0C.rawValue])
        let controller = BatteryController(smc: smc, batteryReader: { (true, 80, true) })
        controller.probe()

        XCTAssertTrue(controller.setChargingEnabled(false).0)

        XCTAssertEqual(smc.writes, [
            .u8(SMCKey.ch0B.rawValue, TC.chargeInhibitByteHigh),
            .u8(SMCKey.ch0C.rawValue, TC.chargeInhibitByteHigh),
        ])
    }
}

private final class BatteryClock {
    var now: TimeInterval = 0
}

private final class FakeBatterySMC: SMCProtocol {
    enum Write: Equatable {
        case u8(String, UInt8)
        case bytes(String, UInt32, [UInt8])
    }

    enum Failure: Error { case write, read }

    let keys: Set<String>
    var failDirectWrite: Bool
    var failUInt8Write: Bool
    var failOnValue: UInt8?
    var failRead = false
    var ignoreOffWrite = false
    var values: [String: UInt8] = [:]
    var reads: [String] = []
    var writes: [Write] = []

    init(
        keys: Set<String>,
        failDirectWrite: Bool = false,
        failUInt8Write: Bool = false
    ) {
        self.keys = keys
        self.failDirectWrite = failDirectWrite
        self.failUInt8Write = failUInt8Write
    }

    func open() throws {}
    func close() {}
    func keyExists(_ key: String) -> Bool { keys.contains(key) }
    func info(_ key: String) throws -> SMCKeyInfo {
        guard keys.contains(key) else { throw Failure.write }
        return SMCKeyInfo(key: key, type: .ui32, dataSize: 4, typeFourCC: "ui32")
    }
    func readBytes(_ key: String) throws -> (SMCKeyInfo, [UInt8]) { throw Failure.write }
    func readUInt8(_ key: String) throws -> UInt8 {
        reads.append(key)
        if failRead { throw Failure.read }
        return values[key] ?? 0
    }
    func readDouble(_ key: String) throws -> Double { 0 }
    func readCelsius(_ key: String) -> Double? { nil }
    func writeUInt8(_ key: String, _ value: UInt8, verify: Bool) throws {
        if failUInt8Write || value == failOnValue { throw Failure.write }
        writes.append(.u8(key, value))
        if value != 0 || !ignoreOffWrite { values[key] = value }
    }
    func writeDouble(_ key: String, _ value: Double, verify: Bool) throws {}
    func writeBytesDirect(_ key: String, size: UInt32, _ bytes: [UInt8]) throws {
        if failDirectWrite { throw Failure.write }
        writes.append(.bytes(key, size, bytes))
    }
    func writeBytes(_ key: String, _ bytes: [UInt8], verify: Bool) throws {}
}
