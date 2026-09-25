import Foundation
#if TESTING
@testable import ThermalControl
#endif

/// Controller seams so `HelperXPCService` (Phase 3) can be exercised with
/// fakes — the real controllers need hardware + FTST/charge-gate timing.

protocol FanControlling {
    var count: Int { get }
    var canControl: Bool { get }
    var ftstPresent: Bool { get }
    var policy: FanPolicy { get }
    func probe()
    func status() -> FanStatus
    func setMode(_ mode: FanMode) -> (Bool, String?)
    @discardableResult func setManual(rpm: Int, index: Int) -> (Bool, String?)
    @discardableResult func restoreSystem() -> (Bool, String?)
    @discardableResult func apply() -> (Bool, String?)
}

protocol BatteryControlling {
    var canControl: Bool { get }
    var family: BatteryFamily { get }
    func probe()
    func status() -> BatteryStatus
    func setLimit(upper: Int, lower: Int) -> (Bool, String?)
    func setChargingEnabled(_ enabled: Bool) -> (Bool, String?)
    func setForceDischarge(_ enabled: Bool) -> (Bool, String?)
    func disableForceDischarge()
    func restoreDefaultCharge()
    func tick()
}

#if !TESTING
extension FanController: FanControlling {}
extension BatteryController: BatteryControlling {}
#endif