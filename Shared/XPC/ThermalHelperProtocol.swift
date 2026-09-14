import Foundation

@objc public protocol ThermalHelperProtocol {
    func ping(_ token: String, reply: @escaping (Bool) -> Void)
    func getCapabilities(reply: @escaping (Capabilities) -> Void)
    func getFanStatus(reply: @escaping (FanStatus) -> Void)
    func setFanMode(_ mode: Int, reply: @escaping (Bool, String?) -> Void)
    func setFanTargetRPM(_ rpm: Int, fanIndex: Int, reply: @escaping (Bool, String?) -> Void)
    func getBatteryStatus(reply: @escaping (BatteryStatus) -> Void)
    func setChargeLimit(_ upper: Int, lower: Int, reply: @escaping (Bool, String?) -> Void)
    func setChargingEnabled(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void)
    func setForceDischarge(_ enabled: Bool, reply: @escaping (Bool, String?) -> Void)
    func restoreSystemControl(reply: @escaping (Bool, String?) -> Void)
    func getThermalSnapshot(reply: @escaping ([TempReading]) -> Void)
}

enum ThermalXPC {
    static func makeInterface() -> NSXPCInterface {
        let iface = NSXPCInterface(with: ThermalHelperProtocol.self)
        allow(iface, #selector(ThermalHelperProtocol.getCapabilities(reply:)), [Capabilities.self])
        allow(iface, #selector(ThermalHelperProtocol.getFanStatus(reply:)), [FanStatus.self, FanChannel.self])
        allow(iface, #selector(ThermalHelperProtocol.getBatteryStatus(reply:)), [BatteryStatus.self])
        allow(iface, #selector(ThermalHelperProtocol.getThermalSnapshot(reply:)), [TempReading.self])
        return iface
    }

    private static func allow(_ iface: NSXPCInterface, _ sel: Selector, _ classes: [AnyClass]) {
        let ns = NSMutableSet()
        iface.classes(for: sel, argumentIndex: 0, ofReply: true).forEach { ns.add($0) }
        classes.forEach { ns.add($0) }
        ns.add(NSArray.self)
        ns.add(NSString.self)
        iface.setClasses(Set(ns.allObjects as! [AnyHashable]), for: sel, argumentIndex: 0, ofReply: true)
    }
}
