import XCTest
@testable import ThermalControl

@MainActor
final class FanViewModelTests: XCTestCase {
    func testNumericDraftAndSelectingFixedRPMNeverSendUntilApply() async {
        let client = FanTestClient(fanCount: 2)
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        vm.selectFanCustom()
        vm.rpmFieldBinding(for: 0).wrappedValue = 2_200
        await Task.yield()
        XCTAssertTrue(client.rpmCommands.isEmpty)
        XCTAssertEqual(vm.desiredFanMode, .system)
        XCTAssertEqual(vm.balancedRPM(for: 1), 2_200)
        vm.apply(status: client.readback!)
        XCTAssertEqual(vm.draftRPM(for: 0), 2_200, "Polling or tab reappearance must not erase drafts")
        vm.setManualRPM()
        await waitUntil { !vm.isApplying }
        XCTAssertEqual(client.rpmCommands, [.init(rpm: 2_200, index: 0), .init(rpm: 2_200, index: 1)])
        XCTAssertEqual(vm.desiredFanMode, .manual)
        XCTAssertNil(vm.errorMessage)
    }

    func testCancelRestoresConfirmedTargetsWithoutWriting() {
        let client = FanTestClient()
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        vm.rpmFieldBinding(for: 0).wrappedValue = 4_000
        vm.cancelFanEdits()
        XCTAssertEqual(vm.draftRPM(for: 0), 2_000)
        XCTAssertFalse(vm.editingFan)
        XCTAssertTrue(client.rpmCommands.isEmpty)
    }

    func testQuickModeWritesImmediatelyWithoutApplyingDraft() async {
        let client = FanTestClient()
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        vm.rpmFieldBinding(for: 0).wrappedValue = 3_100
        vm.setFanMode(.quiet)
        await waitUntil { !vm.isApplying }
        XCTAssertEqual(client.modes, [.quiet])
        XCTAssertTrue(client.rpmCommands.isEmpty)
        XCTAssertEqual(vm.draftRPM(for: 0), 3_100)
        XCTAssertEqual(vm.desiredFanMode, .quiet)
    }

    func testMissingOrMismatchedReadbackDoesNotPersistTargets() async {
        let client = FanTestClient()
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        AppSettings.fanDrafts = [0: 2_000]
        client.updateReadback = false
        vm.setFanRPM(3_100, index: 0)
        await waitUntil { !vm.isApplying }
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(AppSettings.fanDrafts, [0: 2_000])
        XCTAssertNil(host.error, "Feature errors must not become global errors")
        client.readback = nil
        vm.setManualRPM()
        await waitUntil { !vm.isApplying }
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(AppSettings.fanDrafts, [0: 2_000])
    }

    func testConfirmedTargetPersistsWithoutWaitingForPhysicalRPM() async {
        let client = FanTestClient()
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        vm.setFanRPM(3_100, index: 0)
        await waitUntil { !vm.isApplying }
        XCTAssertEqual(client.readback?.fans.first?.actualRPM, 2_000)
        XCTAssertEqual(AppSettings.fanDrafts[0], 3_100)
        XCTAssertNil(vm.errorMessage)
    }

    func testMultiFanFailureReportsPartialAndKeepsDrafts() async {
        let client = FanTestClient(fanCount: 2)
        client.rpmResults = [(false, "fan failed")]
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        vm.fanDrafts = [0: 2_200, 1: 3_300]
        vm.setManualRPM()
        await waitUntil { !vm.isApplying }
        XCTAssertEqual(client.targetCalls, 1)
        XCTAssertEqual(client.rpmCommands, [.init(rpm: 2_200, index: 0), .init(rpm: 2_200, index: 1)])
        XCTAssertEqual(vm.fans.map { Int($0.targetRPM) }, [2_000, 2_000])
        XCTAssertEqual(vm.errorMessage, "fan failed")
        XCTAssertEqual(vm.draftRPM(for: 1), 2_200)
        XCTAssertNil(host.error)
    }

    func testDisconnectedAndCancelledCommandsNeverReplay() async {
        let client = FanTestClient()
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        vm.setFanMode(.max)
        vm.cancelPendingCommands()
        await Task.yield()
        host.isConnected = false
        vm.setFanMode(.quiet)
        vm.setFanRPM(3_000, index: 0)
        host.isConnected = true
        vm.apply(status: client.readback!)
        await Task.yield()
        XCTAssertTrue(client.modes.isEmpty)
        XCTAssertTrue(client.rpmCommands.isEmpty)
        XCTAssertEqual(vm.draftRPM(for: 0), 3_000)
    }

    func testMissingReadbackKeepsSafeQuitCleanupRequired() async {
        let client = FanTestClient()
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        client.readback = nil
        vm.setFanMode(.max)
        await waitUntil { !vm.isApplying }
        XCTAssertEqual(vm.desiredFanMode, .system)
        XCTAssertTrue(vm.hasTransientOverride, "A missing reply does not prove the hardware stayed in Auto")
        vm.cancelPendingCommands()
        XCTAssertTrue(vm.hasTransientOverride)
        let clean = FanTestClient().readback!
        vm.apply(status: clean)
        XCTAssertFalse(vm.hasTransientOverride)
    }

    func testInvalidSensorNumbersDoNotReachNumericEditorsOrCommands() async {
        let client = FanTestClient()
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        client.readback!.fans[0].actualRPM = .nan
        client.readback!.fans[0].targetRPM = .infinity
        client.readback!.fans[0].minRPM = .nan
        client.readback!.fans[0].maxRPM = .infinity
        vm.apply(status: client.readback!)
        XCTAssertEqual(vm.fans[0].actualRPM, 0)
        XCTAssertEqual(vm.fans[0].targetRPM, 0)
        XCTAssertTrue(vm.sliderMin.isFinite)
        XCTAssertTrue(vm.sliderMax.isFinite)
        XCTAssertFalse(vm.hasValidFanLimits)
        vm.setManualRPM()
        await Task.yield()
        XCTAssertTrue(client.rpmCommands.isEmpty)
    }

    func testNewQuickModeSupersedesUnsentFanTargets() async {
        let client = FanTestClient(fanCount: 2)
        client.suspendRPMReply = true
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        vm.fanDrafts = [0: 2_200, 1: 3_300]
        vm.setManualRPM()
        await waitUntil { client.pendingRPMReply != nil }
        vm.setFanMode(.max)
        client.pendingRPMReply?.resume(returning: (true, nil))
        client.pendingRPMReply = nil
        await waitUntil { !vm.isApplying }
        XCTAssertEqual(client.targetCalls, 1)
        XCTAssertEqual(client.rpmCommands.count, 2)
        XCTAssertEqual(client.modes, [.max])
        XCTAssertEqual(vm.desiredFanMode, .max)
        XCTAssertNil(vm.errorMessage)
    }

    func testAcceptedIntermediateRampDoesNotPersistUntilTerminalTargetReadback() async {
        let client = FanTestClient()
        client.rampCommands = true
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        AppSettings.fanDrafts = [0: 2_000]
        vm.setFanRPM(3_000, index: 0)
        await waitUntil { !vm.isApplying }
        XCTAssertTrue(vm.isRamping)
        XCTAssertEqual(vm.desiredFanMode, .manual)
        XCTAssertEqual(vm.goalRPM(for: 0), 3_000)
        XCTAssertEqual(vm.fans[0].targetRPM, 2_000)
        XCTAssertEqual(AppSettings.fanDrafts[0], 2_000)
        XCTAssertNil(vm.errorMessage)
        client.readback!.fans[0].targetRPM = 2_500
        vm.apply(status: client.readback!)
        XCTAssertEqual(AppSettings.fanDrafts[0], 2_000)
        client.readback!.ramping = false
        client.readback!.fans[0].targetRPM = 3_000
        vm.apply(status: client.readback!)
        XCTAssertFalse(vm.isRamping)
        XCTAssertEqual(vm.fans[0].actualRPM, 2_000, "Terminal confirmation concerns hardware target, not physical RPM")
        XCTAssertEqual(AppSettings.fanDrafts[0], 3_000)
        XCTAssertNil(vm.errorMessage)
    }

    func testStalePollCannotReplaceNewerRampGoalsOrCompletedState() async {
        let client = FanTestClient()
        client.rampCommands = true
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        vm.setFanRPM(3_000, index: 0)
        await waitUntil { !vm.isApplying }
        let old = snapshot(client.readback!)
        vm.setFanRPM(4_000, index: 0)
        await waitUntil { !vm.isApplying }
        vm.apply(status: old)
        XCTAssertEqual(vm.goalRPM(for: 0), 4_000)
        XCTAssertEqual(vm.draftRPM(for: 0), 4_000)
        XCTAssertNil(vm.errorMessage)
        let sameTransitionIntermediate = snapshot(client.readback!)
        client.readback!.ramping = false
        client.readback!.fans[0].targetRPM = 4_000
        vm.apply(status: client.readback!)
        vm.apply(status: sameTransitionIntermediate)
        XCTAssertFalse(vm.isRamping)
        XCTAssertEqual(vm.fans[0].targetRPM, 4_000)
        XCTAssertEqual(AppSettings.fanDrafts[0], 4_000)
    }

    func testNewQuickModeDropsOldManualRampPersistence() async {
        let client = FanTestClient()
        client.rampCommands = true
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        AppSettings.fanDrafts = [0: 2_000]
        vm.setFanRPM(4_000, index: 0)
        await waitUntil { !vm.isApplying }
        let stale = snapshot(client.readback!)
        vm.setFanMode(.quiet)
        await waitUntil { !vm.isApplying }
        XCTAssertTrue(vm.isRamping)
        XCTAssertEqual(vm.desiredFanMode, .quiet)
        XCTAssertEqual(vm.goalRPM(for: 0), 1_000)
        stale.ramping = false
        stale.fans[0].targetRPM = 4_000
        vm.apply(status: stale)
        XCTAssertEqual(vm.desiredFanMode, .quiet)
        XCTAssertEqual(vm.goalRPM(for: 0), 1_000)
        XCTAssertEqual(AppSettings.fanDrafts[0], 2_000)
        XCTAssertNil(vm.errorMessage)
    }

    func testPrimaryRPMBalancesTheSecondFanAcrossItsOwnRange() async {
        let client = FanTestClient(fanCount: 2)
        client.readback = FanStatus(fans: [
            FanChannel(index: 0, actualRPM: 2_000, targetRPM: 2_000, minRPM: 1_200, maxRPM: 6_000,
                       modeRaw: FanMode.system.rawValue, modeKey: "F0Md"),
            FanChannel(index: 1, actualRPM: 2_000, targetRPM: 2_000, minRPM: 1_300, maxRPM: 5_500,
                       modeRaw: FanMode.system.rawValue, modeKey: "F1Md")
        ], desiredMode: FanMode.system.rawValue, ftstPresent: false)
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        vm.rpmFieldBinding(for: 0).wrappedValue = 3_600
        XCTAssertEqual(vm.balancedRPM(for: 0), 3_600)
        XCTAssertEqual(vm.balancedRPM(for: 1), 3_400)
        vm.setManualRPM()
        await waitUntil { !vm.isApplying }
        XCTAssertEqual(client.rpmCommands, [.init(rpm: 3_600, index: 0), .init(rpm: 3_400, index: 1)])
    }

    func testMenuCustomUsesHalfRangeWhenNothingIsSaved() async {
        let client = FanTestClient(fanCount: 2)
        client.readback = FanStatus(fans: [
            FanChannel(index: 0, actualRPM: 2_000, targetRPM: 2_000, minRPM: 1_200, maxRPM: 6_000,
                       modeRaw: FanMode.system.rawValue, modeKey: "F0Md"),
            FanChannel(index: 1, actualRPM: 2_000, targetRPM: 2_000, minRPM: 1_300, maxRPM: 5_500,
                       modeRaw: FanMode.system.rawValue, modeKey: "F1Md")
        ], desiredMode: FanMode.system.rawValue, ftstPresent: false)
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        AppSettings.manualRPM = 0
        AppSettings.fanDrafts = [:]
        vm.manualRPM = 2_500
        vm.fanDrafts = [0: 2_000]
        vm.applySavedCustom()
        await waitUntil { !vm.isApplying }
        XCTAssertEqual(client.rpmCommands, [.init(rpm: 3_600, index: 0), .init(rpm: 3_400, index: 1)])
        XCTAssertFalse(vm.editingFan)
        XCTAssertEqual(vm.desiredFanMode, .manual)
    }

    func testAutoRampWithAGoalStaysQuietUntilTheRelease() async {
        let client = FanTestClient()
        client.rampCommands = true
        client.modeGoal = 1_500
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        vm.setFanMode(.system)
        await waitUntil { !vm.isApplying }
        XCTAssertTrue(vm.isRamping)
        XCTAssertEqual(vm.goalRPM(for: 0), 1_500)
        XCTAssertEqual(vm.desiredFanMode, .system)
        XCTAssertTrue(vm.hasTransientOverride)
        XCTAssertNil(vm.errorMessage)
    }

    func testAutoImmediatelySupersedesRampAndDropsPendingPersistence() async {
        let client = FanTestClient()
        client.rampCommands = true
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        AppSettings.fanDrafts = [0: 2_000]
        vm.setFanRPM(5_000, index: 0)
        await waitUntil { !vm.isApplying }
        let stale = snapshot(client.readback!)
        vm.setFanMode(.system)
        await waitUntil { !vm.isApplying }
        XCTAssertEqual(client.modes, [.system])
        XCTAssertFalse(vm.isRamping)
        XCTAssertEqual(vm.desiredFanMode, .system)
        XCTAssertFalse(vm.hasTransientOverride)
        stale.ramping = false
        stale.fans[0].targetRPM = 5_000
        vm.apply(status: stale)
        XCTAssertEqual(vm.desiredFanMode, .system)
        XCTAssertEqual(AppSettings.fanDrafts[0], 2_000)
        XCTAssertNil(vm.errorMessage)
    }

    func testHelperProvidedMaxGoalDefinesEndpointWithoutLooseningReadbackTolerance() async {
        let client = FanTestClient()
        client.modeGoal = 5_998
        client.rampCommands = true
        let host = FanTestHost()
        let vm = makeViewModel(client, host: host)
        vm.setFanMode(.max)
        await waitUntil { !vm.isApplying }
        XCTAssertEqual(vm.goalRPM(for: 0), 5_998)
        XCTAssertTrue(vm.isRamping)
        XCTAssertNil(vm.errorMessage)
        client.readback!.ramping = false
        client.readback!.fans[0].targetRPM = 5_998
        vm.apply(status: client.readback!)
        XCTAssertFalse(vm.isRamping)
        XCTAssertNil(vm.errorMessage)
        vm.setFanMode(.max)
        await waitUntil { !vm.isApplying }
        client.readback!.ramping = false
        client.readback!.fans[0].targetRPM = 5_996
        vm.apply(status: client.readback!)
        XCTAssertNotNil(vm.errorMessage, "Endpoint mismatch must not be hidden by a wider tolerance")
    }

    private func snapshot(_ status: FanStatus) -> FanStatus {
        FanStatus(fans: status.fans.map {
            FanChannel(index: $0.index, actualRPM: $0.actualRPM, targetRPM: $0.targetRPM,
                       minRPM: $0.minRPM, maxRPM: $0.maxRPM, modeRaw: $0.modeRaw,
                       modeKey: $0.modeKey, goalRPM: $0.goalRPM)
        }, desiredMode: status.desiredMode, ftstPresent: status.ftstPresent,
                  lastError: status.lastError, ramping: status.ramping, transitionID: status.transitionID)
    }

    private func makeViewModel(_ client: FanTestClient, host: FanTestHost) -> FanViewModel {
        let savedDrafts = AppSettings.fanDrafts
        let savedRPM = AppSettings.manualRPM
        addTeardownBlock {
            await MainActor.run {
                AppSettings.fanDrafts = savedDrafts
                AppSettings.manualRPM = savedRPM
            }
        }
        let vm = FanViewModel(xpc: client)
        vm.host = host
        vm.fanControl = true
        vm.apply(status: client.readback!)
        return vm
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for fan command")
    }
}

@MainActor
private final class FanTestHost: ViewModelHost {
    var isConnecting = false
    var isConnected = true
    var error: String?
    func noteError(_ message: String) { error = message }
    func surfaceError(_ message: String) { error = message }
    func clearError() { error = nil }
    func batteryChargeDidChange() {}
}

@MainActor
private final class FanTestClient: ThermalHelperClient {
    struct RPMCommand: Equatable { let rpm: Int; let index: Int }
    var modes: [FanMode] = []
    var rpmCommands: [RPMCommand] = []
    var rpmResults: [(Bool, String?)] = []
    var updateReadback = true
    var rampCommands = false
    var modeGoal: Double?
    var readback: FanStatus?
    var suspendRPMReply = false
    var pendingRPMReply: CheckedContinuation<(Bool, String?), Never>?
    var targetCalls = 0

    init(fanCount: Int = 1) {
        readback = FanStatus(fans: (0..<fanCount).map {
            FanChannel(index: $0, actualRPM: 2_000, targetRPM: 2_000, minRPM: 1_000,
                       maxRPM: 6_000, modeRaw: FanMode.system.rawValue, modeKey: "F\($0)Md")
        }, desiredMode: FanMode.system.rawValue, ftstPresent: false)
    }

    func fanStatus() async -> FanStatus? { readback }
    func setFanMode(_ mode: FanMode) async -> (Bool, String?) {
        modes.append(mode)
        if updateReadback, let readback {
            readback.desiredMode = mode.rawValue
            readback.transitionID += 1
            readback.ramping = rampCommands && (mode != .system || modeGoal != nil)
            for fan in readback.fans {
                if mode == .system {
                    fan.goalRPM = modeGoal ?? -1
                } else {
                    fan.goalRPM = modeGoal ?? (mode == .quiet ? fan.minRPM : fan.maxRPM)
                    if !readback.ramping { fan.targetRPM = fan.goalRPM }
                }
            }
        }
        return (true, nil)
    }
    func setFanRPM(_ rpm: Int, index: Int) async -> (Bool, String?) {
        rpmCommands.append(.init(rpm: rpm, index: index))
        let result: (Bool, String?)
        if suspendRPMReply {
            result = await withCheckedContinuation { pendingRPMReply = $0 }
        } else {
            result = rpmResults.isEmpty ? (true, nil) : rpmResults.removeFirst()
        }
        if result.0, updateReadback, let readback {
            readback.desiredMode = FanMode.manual.rawValue
            readback.transitionID += 1
            readback.ramping = rampCommands
            readback.fans.first(where: { $0.index == index })?.goalRPM = Double(rpm)
            if !rampCommands { readback.fans.first(where: { $0.index == index })?.targetRPM = Double(rpm) }
        }
        return result
    }
    func setFanTargets(_ targets: [(index: Int, rpm: Int)]) async -> (Bool, String?) {
        targetCalls += 1
        for target in targets { rpmCommands.append(.init(rpm: target.rpm, index: target.index)) }
        let result: (Bool, String?)
        if suspendRPMReply {
            result = await withCheckedContinuation { pendingRPMReply = $0 }
        } else {
            result = rpmResults.isEmpty ? (true, nil) : rpmResults.removeFirst()
        }
        if result.0, updateReadback, let readback {
            readback.desiredMode = FanMode.manual.rawValue
            readback.transitionID += 1
            readback.ramping = rampCommands
            for target in targets {
                readback.fans.first(where: { $0.index == target.index })?.goalRPM = Double(target.rpm)
                if !rampCommands {
                    readback.fans.first(where: { $0.index == target.index })?.targetRPM = Double(target.rpm)
                }
            }
        }
        return result
    }
    func batteryStatus() async -> BatteryStatus? { nil }
    func setChargeLimit(upper: Int, lower: Int) async -> (Bool, String?) { (true, nil) }
    func setCharging(_ on: Bool) async -> (Bool, String?) { (true, nil) }
    func setForceDischarge(_ on: Bool) async -> (Bool, String?) { (true, nil) }
}
