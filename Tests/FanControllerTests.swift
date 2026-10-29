import XCTest

final class FanControllerTests: XCTestCase {
    func testInvalidIndexNeverWritesHardware() {
        let smc = ControllerTestSMC()
        let fan = FanController(smc: smc)
        fan.probe()
        for index in [-2, 2, Int.max] {
            XCTAssertFalse(fan.setManual(rpm: 2_500, index: index).0)
        }
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testMissingTargetKeyRejectsForcedModesWithoutWrites() {
        let smc = ControllerTestSMC()
        smc.keys.remove("F1Tg")
        let fan = FanController(smc: smc)
        fan.probe()
        XCTAssertFalse(fan.canControl)
        XCTAssertFalse(fan.setMode(.quiet).0)
        XCTAssertFalse(fan.setMode(.max).0)
        XCTAssertFalse(fan.setManual(rpm: 2_500, index: 0).0)
        XCTAssertTrue(smc.writes.isEmpty)
    }

    func testMaxRampsTwoThousandRPMOverEightSecondsWithoutRepeatingHandshake() {
        let smc = ControllerTestSMC()
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()

        XCTAssertTrue(fan.setMode(.max).0)
        XCTAssertTrue(fan.isRamping)
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [2_000, 2_000])
        XCTAssertEqual(fan.status().fans.map(\.goalRPM), [4_000, 4_000])
        let modeWrites = smc.writes.filter { $0.hasSuffix("Md") }.count
        for _ in 0..<32 {
            now += 0.25
            fan.advanceRamp()
        }
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [4_000, 4_000])
        XCTAssertTrue(fan.isRamping, "Endpoint write is not complete before a later exact readback")
        fan.advanceRamp()
        XCTAssertFalse(fan.isRamping)
        XCTAssertEqual(smc.writes.filter { $0.hasSuffix("Md") }.count, modeWrites)
        XCTAssertEqual(smc.targetWrites.filter { $0.key == "F0Tg" }.map(\.value),
                       [2_000] + (1...32).map { 2_000 + Double($0) * 62.5 })
    }

    func testQuietRampsDownOverEightSecondsWithoutUsingLaggingActualRPM() {
        let smc = ControllerTestSMC()
        smc.values["F0Ac"] = 3_000
        smc.values["F1Ac"] = 3_000
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.quiet).0)
        for _ in 0..<32 { now += 0.25; fan.advanceRamp() }
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [1_000, 1_000])
        XCTAssertEqual(fan.status().fans.map(\.actualRPM), [3_000, 3_000])
        fan.advanceRamp()
        XCTAssertFalse(fan.isRamping)
    }

    func testNewDirectionStartsAtAppliedTargetAndStaleTickCannotAdvanceNewTransition() {
        let smc = ControllerTestSMC()
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.max).0)
        let oldID = fan.status().transitionID
        for _ in 0..<4 { now += 0.25; fan.advanceRamp() }
        let modeWrites = smc.writes.filter { $0.hasSuffix("Md") }.count
        XCTAssertTrue(fan.setMode(.quiet).0)
        let newID = fan.status().transitionID
        XCTAssertNotEqual(oldID, newID)
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [2_250, 2_250])
        let writes = smc.writes.count
        now += 0.25
        fan.advanceRamp(transitionID: oldID)
        XCTAssertEqual(smc.writes.count, writes)
        XCTAssertEqual(fan.status().transitionID, newID)
        XCTAssertTrue(fan.isRamping)
        fan.advanceRamp(transitionID: newID)
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [2_187.5, 2_187.5])
        XCTAssertEqual(smc.writes.filter { $0.hasSuffix("Md") }.count, modeWrites)
        XCTAssertFalse(smc.modes.values.contains(0))
    }

    func testAutoCancelsRampAndRejectsLateTickWithoutTargetWrite() {
        let smc = ControllerTestSMC()
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.max).0)
        let id = fan.status().transitionID
        XCTAssertTrue(fan.restoreSystem().0)
        let writes = smc.writes.count
        now = 10
        fan.advanceRamp(transitionID: id)
        fan.advanceRamp()
        XCTAssertEqual(smc.writes.count, writes)
        XCTAssertFalse(fan.isRamping)
        XCTAssertEqual(fan.policy, .system)
        XCTAssertEqual(smc.modes, ["F0Md": 0, "F1Md": 0])
        XCTAssertEqual(fan.status().fans.map(\.goalRPM), [-1, -1])
    }

    func testDelayedTickIsCappedAndWatchdogReassertsCurrentWithoutRestartingClock() {
        let smc = ControllerTestSMC()
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.max).0)
        let id = fan.status().transitionID
        now = 8
        fan.advanceRamp()
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [2_062.5, 2_062.5])
        fan.advanceRamp() // Confirm the issued step before watchdog reassertion.
        smc.values["F0Tg"] = 0
        now += 0.125
        XCTAssertTrue(fan.apply().0)
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [2_062.5, 2_062.5])
        XCTAssertEqual(fan.status().transitionID, id)
        now += 0.125
        fan.advanceRamp()
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [2_125, 2_125])
        XCTAssertTrue(fan.isRamping)
    }

    func testSingleFanEditKeepsOtherFansOwnGoalInsteadOfCopyingEditedRPM() {
        let smc = ControllerTestSMC()
        smc.values["F1Ac"] = 3_000
        let fan = FanController(smc: smc, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setManual(rpm: 2_500, index: 0).0)
        XCTAssertEqual(fan.status().fans.map(\.goalRPM), [2_500, 3_000])
        XCTAssertTrue(fan.setMode(.quiet).0)
        XCTAssertTrue(fan.setManual(rpm: 3_500, index: 0).0)
        XCTAssertEqual(fan.status().fans.map(\.goalRPM), [3_500, 1_000])
    }

    func testProbeInvalidatesRampWithoutWritingOrRestartingThroughApply() {
        let smc = ControllerTestSMC()
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.max).0)
        let id = fan.status().transitionID
        let writes = smc.writes.count
        fan.probe()
        now = 1
        fan.advanceRamp(transitionID: id)
        XCTAssertFalse(fan.apply().0)
        XCTAssertEqual(smc.writes.count, writes)
        XCTAssertFalse(fan.isRamping)
        XCTAssertEqual(fan.status().fans.map(\.goalRPM), [-1, -1])
    }

    func testTargetWriteFailureStopsRampAndHoldsLastAppliedRPM() {
        let smc = ControllerTestSMC()
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.max).0)
        smc.failKey = "F1Tg"
        now = 0.25
        fan.advanceRamp()
        XCTAssertFalse(fan.isRamping)
        XCTAssertEqual(fan.policy, .max)
        XCTAssertNotNil(fan.status().lastError)
        XCTAssertFalse(smc.modes.values.contains(0))
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [2_062.5, 2_000])
        XCTAssertEqual(fan.status().fans.map(\.goalRPM), [2_062.5, 2_000])
        let writes = smc.writes.count
        now = 2
        fan.advanceRamp()
        XCTAssertEqual(smc.writes.count, writes)
    }

    func testReadbackMismatchSmallerThanOneRPMFailsInsteadOfUsingBroadTolerance() {
        let smc = ControllerTestSMC()
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.max).0)
        now = 0.25
        fan.advanceRamp()
        smc.targetReadbackOffset = 0.25
        now = 1
        fan.advanceRamp()
        XCTAssertTrue(fan.isRamping)
        XCTAssertNil(fan.lastError)
        now = 1.25
        fan.advanceRamp()
        XCTAssertEqual(fan.policy, .max)
        XCTAssertFalse(fan.isRamping)
        XCTAssertFalse(smc.modes.values.contains(0))
        let error = fan.status().lastError ?? ""
        XCTAssertTrue(error.contains("F0Tg"), error)
        XCTAssertTrue(error.contains("expected=2125.0 actual=2125.25"), error)
        XCTAssertTrue(error.contains("type=flt  size=4"))
    }

    func testStaleTargetReadbackWaitsForExactAckWithoutWritingAnotherStep() {
        let smc = ControllerTestSMC()
        smc.values["F0Tg"] = 2_317
        smc.values["F1Tg"] = 2_317
        smc.targetReadLag = 1
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.max).0)
        XCTAssertNil(fan.lastError)
        let writes = smc.targetWrites.count
        now = 0.25
        fan.advanceRamp()
        XCTAssertEqual(smc.targetWrites.count, writes + 2)
        XCTAssertEqual(smc.targetWrites.last?.value, 2_062.5)
        XCTAssertTrue(fan.isRamping)
        now = 0.5
        fan.advanceRamp()
        XCTAssertEqual(smc.targetWrites.last?.value, 2_125)
        XCTAssertNil(fan.lastError)
    }

    func testNewDirectionPreservesPendingWriteWithoutReissuingIt() {
        let smc = ControllerTestSMC()
        // A stale read must differ from the issued 2_000 RPM baseline to remain unacknowledged.
        smc.values["F0Tg"] = 2_317
        smc.values["F1Tg"] = 2_317
        smc.targetReadLag = 1
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.max).0)
        let writes = smc.targetWrites.count
        XCTAssertTrue(fan.setMode(.quiet).0)
        XCTAssertEqual(smc.targetWrites.count, writes)
        now = 0.25
        fan.advanceRamp()
        XCTAssertEqual(smc.targetWrites.last?.value, 1_937.5)
        now = 0.5
        fan.advanceRamp()
        XCTAssertEqual(smc.targetWrites.last?.value, 1_875)
    }

    func testAutoWaitsForDelayedModeReadbackWithoutRewritingMode() {
        let smc = ControllerTestSMC()
        smc.modes = ["F0Md": 1, "F1Md": 1]
        smc.modeReadLag = 1
        let fan = FanController(smc: smc, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.restoreSystem().0)
        XCTAssertEqual(smc.writes, ["F0Md", "F1Md"])
        XCTAssertEqual(smc.modes, ["F0Md": 0, "F1Md": 0])
    }

    func testRestoreFailureReportsExactModeReadback() {
        let smc = ControllerTestSMC()
        smc.ignoredModeWrites = ["F0Md"]
        smc.modes["F0Md"] = 3
        let fan = FanController(smc: smc, scheduleAutomatic: false)
        fan.probe()
        let result = fan.restoreSystem()
        XCTAssertFalse(result.0)
        XCTAssertEqual(result.1, "fan0: Verify fail F0Md: expected=0 actual=3")
        XCTAssertEqual(smc.modes["F1Md"], 0)
    }

    func testStoppedSystemFansStartAtHardwareMinimumThenRamp() {
        let smc = ControllerTestSMC()
        for index in 0..<2 {
            smc.values["F\(index)Ac"] = 0
            smc.values["F\(index)Tg"] = 0
        }
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        let result = fan.setMode(.max)
        XCTAssertTrue(result.0, result.1 ?? "Stopped Auto fans must accept a supported mode")
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [1_000, 1_000])
        XCTAssertEqual(fan.status().fans.map(\.goalRPM), [4_000, 4_000])
        now = 0.25
        fan.advanceRamp()
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [1_062.5, 1_062.5])
        XCTAssertTrue(smc.targetWrites.allSatisfy { $0.value >= 1_000 })
    }

    func testSingleFanEditAcceptsOtherStoppedFanWithoutCopyingRequestedRPM() {
        let smc = ControllerTestSMC()
        smc.values["F0Ac"] = 0
        smc.values["F1Ac"] = 0
        let fan = FanController(smc: smc, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setManual(rpm: 2_500, index: 0).0)
        XCTAssertEqual(fan.status().fans.map(\.goalRPM), [2_500, 1_000])
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [1_000, 1_000])
    }

    func testBaselineReadFailureAndInvalidSensorValuesNeverWriteTargets() {
        for invalid in [Double.nan, Double.infinity, -1] {
            let smc = ControllerTestSMC()
            smc.values["F0Ac"] = invalid
            let fan = FanController(smc: smc, scheduleAutomatic: false)
            fan.probe()
            XCTAssertFalse(fan.setMode(.max).0)
            XCTAssertTrue(smc.targetWrites.isEmpty)
            XCTAssertTrue(smc.writes.isEmpty)
            XCTAssertEqual(fan.policy, .system)
            let error = fan.status().lastError ?? ""
            XCTAssertTrue(error.contains("F0Ac"), error)
            XCTAssertFalse(error.contains("F0Md"), error)
        }
        let smc = ControllerTestSMC()
        smc.readFailKey = "F1Mn"
        let fan = FanController(smc: smc, scheduleAutomatic: false)
        fan.probe()
        XCTAssertFalse(fan.setMode(.max).0)
        XCTAssertTrue(smc.targetWrites.isEmpty)
        XCTAssertTrue(smc.writes.isEmpty)
        XCTAssertEqual(fan.policy, .system)
        let error = fan.status().lastError ?? ""
        XCTAssertTrue(error.contains("F1Mn"), error)
        XCTAssertFalse(error.contains("F0Ac"), error)
    }

    func testSetManualTargetsRampsBothFansTogether() {
        let smc = ControllerTestSMC()
        smc.values["F0Mn"] = 1_200
        smc.values["F0Mx"] = 6_000
        smc.values["F1Mn"] = 1_300
        smc.values["F1Mx"] = 5_500
        let fan = FanController(smc: smc, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setManual(targets: [0: 3_600, 1: 3_400]).0)
        XCTAssertEqual(fan.status().fans.map { Int($0.goalRPM.rounded()) }, [3_600, 3_400])
        let modeWrites = smc.writes.filter { $0.hasSuffix("Md") }.count
        XCTAssertEqual(modeWrites, 2)
    }

    func testAutoRampsToSampledTargetThenReleases() {
        let smc = ControllerTestSMC()
        smc.autoTargets = [0: 1_500, 1: 1_500]
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.max).0)
        XCTAssertTrue(fan.setMode(.system).0)
        XCTAssertEqual(smc.modes, ["F0Md": 1, "F1Md": 1])
        XCTAssertEqual(fan.policy, .max)
        XCTAssertEqual(fan.status().desiredMode, FanMode.system.rawValue)
        XCTAssertEqual(fan.status().fans.map(\.goalRPM), [1_500, 1_500])
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [2_000, 2_000])
        for _ in 0..<8 { now += 0.25; fan.advanceRamp() }
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [1_500, 1_500])
        XCTAssertEqual(smc.modes["F0Md"], 1)
        fan.advanceRamp()
        XCTAssertFalse(fan.isRamping)
        XCTAssertEqual(fan.policy, .system)
        XCTAssertEqual(smc.modes, ["F0Md": 0, "F1Md": 0])
    }

    func testModeChangeDuringAutoReturnRampsTowardTheNewTarget() {
        let smc = ControllerTestSMC()
        smc.autoTargets = [0: 1_500, 1: 1_500]
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.max).0)
        XCTAssertTrue(fan.setMode(.system).0)
        now += 0.25
        fan.advanceRamp()
        XCTAssertTrue(fan.setMode(.quiet).0)
        XCTAssertEqual(fan.policy, .quiet)
        XCTAssertEqual(fan.status().desiredMode, FanMode.quiet.rawValue)
        XCTAssertEqual(fan.status().fans.map(\.targetRPM), [1_937.5, 1_937.5])
        XCTAssertEqual(fan.status().fans.map(\.goalRPM), [1_000, 1_000])
        XCTAssertEqual(smc.modes["F0Md"], 1)
    }

    func testFPE2TargetUsesExactRepresentableEncodingWithinFractionalLimits() {
        let smc = ControllerTestSMC()
        smc.targetType = .fpe2
        smc.values["F0Ac"] = 2_000.1
        smc.values["F0Mn"] = 1_000.1
        smc.values["F0Mx"] = 2_062.4
        var now = 0.0
        let fan = FanController(smc: smc, monotonicNow: { now }, scheduleAutomatic: false)
        fan.probe()
        XCTAssertTrue(fan.setMode(.max).0)
        XCTAssertEqual(fan.status().fans[0].targetRPM, 2_000)
        XCTAssertEqual(fan.status().fans[0].goalRPM, 2_062)
        now = 0.25
        fan.advanceRamp()
        XCTAssertEqual(fan.status().fans[0].targetRPM, 2_062)
        XCTAssertNil(fan.status().lastError)
        XCTAssertTrue(smc.targetWrites.filter { $0.key == "F0Tg" }.allSatisfy {
            $0.value >= 1_000.1 && $0.value <= 2_062.4
        })
    }

    func testRestoreTriesSecondFanAfterFirstWriteFails() {
        let smc = ControllerTestSMC()
        let fan = FanController(smc: smc)
        fan.probe()
        smc.failKey = "F0Md"

        XCTAssertFalse(fan.restoreSystem().0)
        XCTAssertEqual(smc.writes, ["F0Md", "F1Md"])
    }
}

final class ControllerTestSMC: SMCProtocol {
    var writes: [String] = []
    var failKey: String?
    var readFailKey: String?
    var targetReadbackOffset = 0.0
    var targetType = SMCType.flt
    var targetWrites: [(key: String, value: Double)] = []
    var modes: [String: UInt8] = [:]
    var ignoredModeWrites: Set<String> = []
    var targetReadLag = 0
    var modeReadLag = 0
    var autoTargets: [Int: Double] = [:]
    private var staleTargets: [String: (value: Double, remaining: Int)] = [:]
    private var staleModes: [String: (value: UInt8, remaining: Int)] = [:]
    var values: [String: Double] = ["F0Ac": 2_000, "F1Ac": 2_000,
                                    "F0Mn": 1_000, "F1Mn": 1_000,
                                    "F0Mx": 4_000, "F1Mx": 4_000,
                                    "F0Tg": 2_000, "F1Tg": 2_000]
    var keys: Set<String> = ["F0Md", "F1Md", "F0Tg", "F1Tg"]
    func open() throws {}
    func close() {}
    func keyExists(_ key: String) -> Bool { keys.contains(key) }
    func info(_ key: String) throws -> SMCKeyInfo {
        SMCKeyInfo(key: key, type: targetType, dataSize: targetType == .flt ? 4 : targetType == .ui8 ? 1 : 2,
                   typeFourCC: targetType == .flt ? "flt " : targetType == .ui8 ? "ui8 " : "fpe2")
    }
    func readBytes(_ key: String) throws -> (SMCKeyInfo, [UInt8]) { throw CocoaError(.fileReadUnknown) }
    func readUInt8(_ key: String) throws -> UInt8 {
        if key == SMCKey.fanCount.rawValue { return 2 }
        if var stale = staleModes[key], stale.remaining > 0 {
            stale.remaining -= 1
            staleModes[key] = stale
            return stale.value
        }
        return modes[key] ?? 0
    }
    func readDouble(_ key: String) throws -> Double {
        if key == readFailKey { throw CocoaError(.fileReadUnknown) }
        if var stale = staleTargets[key], stale.remaining > 0 {
            stale.remaining -= 1
            staleTargets[key] = stale
            return stale.value
        }
        return (values[key] ?? 2_000) + (key.hasSuffix("Tg") ? targetReadbackOffset : 0)
    }
    func readCelsius(_ key: String) -> Double? { nil }
    func writeUInt8(_ key: String, _ value: UInt8, verify: Bool) throws {
        writes.append(key)
        if key == failKey { throw CocoaError(.fileWriteUnknown) }
        if !ignoredModeWrites.contains(key) {
            staleModes[key] = (modes[key] ?? 0, modeReadLag)
            modes[key] = value
        }
        if value == 0, key.count >= 3, key.hasPrefix("F"),
           let index = Int(String(key[key.index(key.startIndex, offsetBy: 1)])),
           let auto = autoTargets[index] {
            values["F\(index)Tg"] = auto
        }
    }
    func writeDouble(_ key: String, _ value: Double, verify: Bool) throws {
        writes.append(key)
        if key == failKey { throw CocoaError(.fileWriteUnknown) }
        let encoded: Double
        switch targetType {
        case .flt: encoded = Double(Float(value))
        case .fpe2: encoded = (value * 4).rounded() / 4
        default: encoded = value.rounded()
        }
        staleTargets[key] = (values[key] ?? 2_000, targetReadLag)
        values[key] = encoded
        targetWrites.append((key, encoded))
    }
    func writeBytesDirect(_ key: String, size: UInt32, _ bytes: [UInt8]) throws { writes.append(key) }
    func writeBytes(_ key: String, _ bytes: [UInt8], verify: Bool) throws { writes.append(key) }
}
