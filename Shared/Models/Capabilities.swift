import Foundation

@objc(TCCapabilities)
public final class Capabilities: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public var fanCount: Int
    @objc public var fanControl: Bool
    @objc public var ftstPresent: Bool
    @objc public var batteryPresent: Bool
    @objc public var batteryControl: Bool
    @objc public var batteryFamily: String
    @objc public var helperVersion: String
    @objc public var protocolVersion: Int

    public init(fanCount: Int, fanControl: Bool, ftstPresent: Bool, batteryPresent: Bool, batteryControl: Bool, batteryFamily: String, helperVersion: String, protocolVersion: Int = 2) {
        self.fanCount = fanCount
        self.fanControl = fanControl
        self.ftstPresent = ftstPresent
        self.batteryPresent = batteryPresent
        self.batteryControl = batteryControl
        self.batteryFamily = batteryFamily
        self.helperVersion = helperVersion
        self.protocolVersion = protocolVersion
    }

    public required init?(coder: NSCoder) {
        fanCount = coder.decodeInteger(forKey: "fanCount")
        fanControl = coder.decodeBool(forKey: "fanControl")
        ftstPresent = coder.decodeBool(forKey: "ftstPresent")
        batteryPresent = coder.decodeBool(forKey: "batteryPresent")
        batteryControl = coder.decodeBool(forKey: "batteryControl")
        batteryFamily = (coder.decodeObject(of: NSString.self, forKey: "batteryFamily") as String?) ?? "none"
        helperVersion = (coder.decodeObject(of: NSString.self, forKey: "helperVersion") as String?) ?? "0"
        let pv = coder.decodeInteger(forKey: "protocolVersion")
        protocolVersion = pv == 0 ? 2 : pv
    }

    public func encode(with coder: NSCoder) {
        coder.encode(fanCount, forKey: "fanCount")
        coder.encode(fanControl, forKey: "fanControl")
        coder.encode(ftstPresent, forKey: "ftstPresent")
        coder.encode(batteryPresent, forKey: "batteryPresent")
        coder.encode(batteryControl, forKey: "batteryControl")
        coder.encode(batteryFamily as NSString, forKey: "batteryFamily")
        coder.encode(helperVersion as NSString, forKey: "helperVersion")
        coder.encode(protocolVersion, forKey: "protocolVersion")
    }
}
