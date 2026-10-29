import Foundation

/// Controller seams so `HelperXPCService` and `SafetyWatchdog` can be exercised
/// with fakes in tests.
protocol FanControlling {
    var count: Int { get }
    var canControl: Bool { get }
    var ftstPresent: Bool { get }
    var policy: FanPolicy { get }
    var isRamping: Bool { get }
    func probe()
    func status() -> FanStatus
    func setMode(_ mode: FanMode) -> (Bool, String?)
    @discardableResult func setManual(rpm: Int, index: Int) -> (Bool, String?)
    @discardableResult func setManual(targets: [Int: Int]) -> (Bool, String?)
    @discardableResult func restoreSystem() -> (Bool, String?)
    @discardableResult func apply() -> (Bool, String?)
}

extension FanControlling {
    var isRamping: Bool { status().ramping }

    @discardableResult
    func setManual(targets: [Int: Int]) -> (Bool, String?) {
        var last: (Bool, String?) = (false, "Invalid fan target")
        for (index, rpm) in targets.sorted(by: { $0.key < $1.key }) {
            last = setManual(rpm: rpm, index: index)
            if !last.0 { return last }
        }
        return last
    }
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
    @discardableResult func stopForceDischarge() -> (Bool, String?)
    @discardableResult func restoreDefaultCharge() -> (Bool, String?)
    func tick()
}

extension BatteryControlling {
    @discardableResult
    func stopForceDischarge() -> (Bool, String?) {
        (false, "Controller không hỗ trợ xác minh dừng xả pin")
    }
}
