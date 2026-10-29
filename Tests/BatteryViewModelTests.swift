import XCTest
@testable import ThermalControl

@MainActor
final class BatteryViewModelTests: XCTestCase {
    func testStartupAndReconnectNeverReplayChargeIntent() async {
        let client = FakeThermalHelperClient()
        let host = FakeViewModelHost(isConnecting: true)
        let vm = makeViewModel(client, host: host)
        vm.setChargeCustom(85)
        vm.setChargeFull()
        host.isConnecting = false
        host.isConnected = true
        vm.helperDidBecomeReady()
        await Task.yield()
        XCTAssertTrue(client.chargeLimits.isEmpty)
        XCTAssertTrue(client.chargingCommands.isEmpty)
        XCTAssertEqual(vm.chargeMode, .full)
    }

    func testDraftsStayLocalAcrossStatusAndCancelRestoresCommittedLimits() async {
        let client = FakeThermalHelperClient()
        let host = FakeViewModelHost(isConnected: true)
        let vm = makeViewModel(client, host: host)
        vm.beginChargeEdits()
        vm.chargePercentBinding.wrappedValue = 90
        vm.chargeLowerBinding.wrappedValue = 75
        vm.apply(status: client.readback!)
        await Task.yield()
        XCTAssertEqual(vm.savedChargeUpper, 90)
        XCTAssertEqual(vm.draftChargeLower, 75)
        XCTAssertTrue(client.chargeLimits.isEmpty)
        vm.cancelChargeEdits()
        XCTAssertEqual(vm.savedChargeUpper, 80)
        XCTAssertEqual(vm.draftChargeLower, 70)
        XCTAssertFalse(vm.editingCharge)
    }

    func testApplyClampsDraftWithSharedContract() async {
        let client = FakeThermalHelperClient()
        let host = FakeViewModelHost(isConnected: true)
        let vm = makeViewModel(client, host: host)
        vm.savedChargeUpper = 10
        vm.draftChargeLower = 99
        vm.applyChargeLimit()
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(client.chargeLimits.first?.0, 40)
        XCTAssertEqual(client.chargeLimits.first?.1, 35)
        XCTAssertEqual(vm.chargeUpper, 40)
        XCTAssertEqual(vm.chargeLower, 35)
        vm.savedChargeUpper = 100
        vm.draftChargeLower = 0
        vm.applyChargeLimit()
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(client.chargeLimits.last?.0, 99)
        XCTAssertEqual(client.chargeLimits.last?.1, 20)
    }

    func testQuickLimitUsesCommittedPolicyNotUnappliedDraft() async {
        let client = FakeThermalHelperClient()
        let host = FakeViewModelHost(isConnected: true)
        let vm = makeViewModel(client, host: host)
        vm.chargePercentBinding.wrappedValue = 90
        vm.chargeLowerBinding.wrappedValue = 85
        vm.setChargeCustom()
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(client.chargeLimits.first?.0, 80)
        XCTAssertEqual(client.chargeLimits.first?.1, 70)
        XCTAssertEqual(vm.savedChargeUpper, 90)
        XCTAssertEqual(vm.draftChargeLower, 85)
    }

    func testMismatchedOrMissingReadbackDoesNotPersist() async {
        let client = FakeThermalHelperClient()
        client.updateReadback = false
        let host = FakeViewModelHost(isConnected: true)
        let vm = makeViewModel(client, host: host)
        AppSettings.chargeUpper = 80
        vm.setChargeCustom(85)
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(AppSettings.chargeUpper, 80)
        XCTAssertEqual(vm.chargeMode, .full)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(host.error)
        client.readback = nil
        vm.setChargeCustom(90)
        await waitUntil { !vm.applyingCharge }
        XCTAssertFalse(vm.hasConfirmedChargeState)
        XCTAssertEqual(AppSettings.chargeUpper, 80)
    }

    func testPolicyConfirmationDoesNotRequirePhysicalChargingCurrent() async {
        let client = FakeThermalHelperClient()
        let host = FakeViewModelHost(isConnected: true)
        let vm = makeViewModel(client, host: host)
        vm.setChargeCustom(80)
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(vm.chargeMode, .custom)
        XCTAssertFalse(vm.chargingEnabled, "Physical gate can stay off at the target")
        XCTAssertEqual(vm.amperageMA, 0)
        XCTAssertNil(vm.errorMessage)
        vm.setChargeFull()
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(vm.chargeMode, .full)
        XCTAssertNil(vm.errorMessage, "Full policy is not a promise of positive charging current")
    }

    func testCancellationBeforeTaskStartsNeverWrites() async {
        let client = FakeThermalHelperClient()
        let host = FakeViewModelHost(isConnected: true)
        let vm = makeViewModel(client, host: host)
        vm.setChargeCustom(85)
        vm.cancelPendingCommands()
        vm.helperDidBecomeReady()
        await Task.yield()
        XCTAssertTrue(client.chargeLimits.isEmpty)
    }

    func testDischargeRequiresConfirmedLimitACAndBatteryAboveTarget() async {
        let client = FakeThermalHelperClient()
        let host = FakeViewModelHost(isConnected: true)
        let vm = makeViewModel(client, host: host)
        vm.setForceDischarge(true)
        XCTAssertTrue(client.dischargeCommands.isEmpty)
        client.readback!.maintainActive = true
        client.readback!.upperLimit = 80
        client.readback!.percent = 90
        vm.apply(status: client.readback!)
        vm.externalAC = false
        XCTAssertFalse(vm.canStartDischarge)
        vm.externalAC = true
        vm.batteryPercent = 80
        XCTAssertFalse(vm.canStartDischarge)
        vm.batteryPercent = 90
        vm.setForceDischarge(true)
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(client.dischargeCommands, [true])
        XCTAssertTrue(vm.forceDischarge)
        XCTAssertEqual(vm.dischargeTargetPercent, 80)
        XCTAssertEqual(vm.dischargeRemainingSeconds, 3_600)
    }

    func testMissingDischargeReadbackRetainsStopAndQuitCleanup() async {
        let client = FakeThermalHelperClient()
        client.readback!.maintainActive = true
        client.readback!.upperLimit = 80
        client.readback!.percent = 90
        let host = FakeViewModelHost(isConnected: true)
        let vm = makeViewModel(client, host: host)
        client.readback = nil
        vm.setForceDischarge(true)
        await waitUntil { !vm.applyingCharge }
        XCTAssertTrue(vm.hasTransientOverride)
        XCTAssertTrue(vm.needsDischargeStop)
        XCTAssertFalse(vm.dischargeStopVerified)
        vm.cancelPendingCommands()
        XCTAssertTrue(vm.hasTransientOverride)
    }

    func testStopRemainsAvailableWithoutCapabilityAndDoesNotFakeOff() async {
        let client = FakeThermalHelperClient()
        let host = FakeViewModelHost(isConnected: true)
        let vm = makeViewModel(client, host: host)
        client.readback!.forceDischarge = true
        client.readback!.dischargeStopVerified = false
        client.readback!.canControlCharge = false
        client.readback!.canForceDischarge = false
        client.updateReadback = false
        client.dischargeResult = (false, "stop failed")
        vm.apply(status: client.readback!)
        vm.batteryControl = false
        vm.forceDischargeControl = false
        vm.setForceDischarge(false)
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(client.dischargeCommands, [false])
        XCTAssertTrue(vm.needsDischargeStop)
        XCTAssertTrue(vm.forceDischarge)
        XCTAssertFalse(vm.dischargeStopVerified)
        XCTAssertEqual(vm.errorMessage, "stop failed")
    }

    func testMenuPresetsApplyTenPointGapAndHighlightOnlyExactValues() async {
        let client = FakeThermalHelperClient()
        let host = FakeViewModelHost(isConnected: true)
        let vm = makeViewModel(client, host: host)
        vm.applyMenuPreset(upper: 60)
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(client.chargeLimits.first?.0, 60)
        XCTAssertEqual(client.chargeLimits.first?.1, 50)
        XCTAssertTrue(vm.menuPresetIsSelected(upper: 60))
        XCTAssertFalse(vm.menuPresetIsSelected(upper: 80))
        vm.applyMenuPreset(upper: 80)
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(client.chargeLimits.last?.0, 80)
        XCTAssertEqual(client.chargeLimits.last?.1, 70)
        vm.applyMenuPreset(upper: 90)
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(client.chargeLimits.last?.0, 90)
        XCTAssertEqual(client.chargeLimits.last?.1, 80)
        XCTAssertTrue(vm.menuPresetIsSelected(upper: 90))
        vm.setChargeFull()
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(vm.chargeMode, .full)
        XCTAssertFalse(vm.menuPresetIsSelected(upper: 90))
        vm.chargeMode = .custom
        vm.chargeUpper = 75
        XCTAssertFalse(vm.menuPresetIsSelected(upper: 60))
        XCTAssertFalse(vm.menuPresetIsSelected(upper: 80))
        XCTAssertFalse(vm.menuPresetIsSelected(upper: 90))
    }

    func testMenuLimitStartsAtSixtyUnlessAPresetWasSaved() async {
        let client = FakeThermalHelperClient()
        let host = FakeViewModelHost(isConnected: true)
        let vm = makeViewModel(client, host: host)
        let savedUpper = AppSettings.chargeUpper
        addTeardownBlock { await MainActor.run { AppSettings.chargeUpper = savedUpper } }
        AppSettings.chargeUpper = nil
        vm.chargeMode = .full
        vm.selectMenuLimit()
        await waitUntil { !vm.applyingCharge }
        XCTAssertEqual(client.chargeLimits.first?.0, 60)
        XCTAssertEqual(client.chargeLimits.first?.1, 50)
        AppSettings.chargeUpper = 80
        vm.chargeMode = .full
        vm.selectMenuLimit()
        await waitUntil { client.chargeLimits.count == 2 && !vm.applyingCharge }
        XCTAssertEqual(client.chargeLimits.last?.0, 80)
        XCTAssertEqual(client.chargeLimits.last?.1, 70)
        let count = client.chargeLimits.count
        vm.chargeMode = .custom
        vm.chargeUpper = 75
        vm.selectMenuLimit()
        XCTAssertEqual(client.chargeLimits.count, count)
    }

    private func makeViewModel(_ client: FakeThermalHelperClient, host: FakeViewModelHost) -> BatteryViewModel {
        let upper = AppSettings.chargeUpper
        let lower = AppSettings.chargeLower
        let mode = AppSettings.chargeMode
        let saved = AppSettings.savedChargeUpper
        addTeardownBlock {
            await MainActor.run {
                AppSettings.chargeUpper = upper
                AppSettings.chargeLower = lower
                AppSettings.chargeMode = mode
                AppSettings.savedChargeUpper = saved
            }
        }
        let vm = BatteryViewModel(xpc: client)
        vm.host = host
        vm.batteryControl = true
        vm.forceDischargeControl = true
        vm.apply(status: client.readback!)
        return vm
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for battery command")
    }
}

@MainActor
private final class FakeViewModelHost: ViewModelHost {
    var isConnecting: Bool
    var isConnected: Bool
    var error: String?
    init(isConnecting: Bool = false, isConnected: Bool = false) {
        self.isConnecting = isConnecting
        self.isConnected = isConnected
    }
    func noteError(_ message: String) { error = message }
    func surfaceError(_ message: String) { error = message }
    func clearError() { error = nil }
    func batteryChargeDidChange() {}
}

@MainActor
private final class FakeThermalHelperClient: ThermalHelperClient {
    var chargeLimits: [(Int, Int)] = []
    var chargingCommands: [Bool] = []
    var dischargeCommands: [Bool] = []
    var dischargeResult: (Bool, String?) = (true, nil)
    var updateReadback = true
    var readback: BatteryStatus? = BatteryStatus(
        present: true, percent: 50, externalAC: true, amperageMA: 0, voltageMV: 12_000,
        upperLimit: 100, lowerLimit: 95, chargingEnabled: false, maintainActive: false,
        forceDischarge: false, keyFamily: BatteryFamily.tahoe.rawValue,
        canControlCharge: true, canForceDischarge: true, dischargeStopVerified: true
    )

    func fanStatus() async -> FanStatus? { nil }
    func setFanMode(_ mode: FanMode) async -> (Bool, String?) { (true, nil) }
    func setFanRPM(_ rpm: Int, index: Int) async -> (Bool, String?) { (true, nil) }
    func setFanTargets(_ targets: [(index: Int, rpm: Int)]) async -> (Bool, String?) { (true, nil) }
    func batteryStatus() async -> BatteryStatus? { readback }
    func setChargeLimit(upper: Int, lower: Int) async -> (Bool, String?) {
        chargeLimits.append((upper, lower))
        if updateReadback {
            readback?.upperLimit = upper
            readback?.lowerLimit = lower
            readback?.maintainActive = true
        }
        return (true, nil)
    }
    func setCharging(_ on: Bool) async -> (Bool, String?) {
        chargingCommands.append(on)
        if updateReadback {
            readback?.maintainActive = false
            readback?.upperLimit = 100
            readback?.lowerLimit = 95
        }
        return (true, nil)
    }
    func setForceDischarge(_ on: Bool) async -> (Bool, String?) {
        dischargeCommands.append(on)
        if dischargeResult.0, updateReadback {
            readback?.forceDischarge = on
            readback?.dischargeStopVerified = !on
            readback?.dischargeTargetPercent = on ? readback?.upperLimit ?? -1 : -1
            readback?.dischargeRemainingSeconds = on ? 3_600 : 0
        }
        return dischargeResult
    }
}
