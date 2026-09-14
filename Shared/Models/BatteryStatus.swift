import Foundation

@objc(TCBatteryStatus)
public final class BatteryStatus: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public var present: Bool
    @objc public var percent: Int
    @objc public var externalAC: Bool
    @objc public var amperageMA: Double
    @objc public var voltageMV: Double
    @objc public var upperLimit: Int
    @objc public var lowerLimit: Int
    @objc public var chargingEnabled: Bool
    @objc public var maintainActive: Bool
    @objc public var forceDischarge: Bool
    @objc public var keyFamily: String
    @objc public var lastError: String?

    public init(
        present: Bool, percent: Int, externalAC: Bool, amperageMA: Double, voltageMV: Double,
        upperLimit: Int, lowerLimit: Int, chargingEnabled: Bool, maintainActive: Bool,
        forceDischarge: Bool, keyFamily: String, lastError: String? = nil
    ) {
        self.present = present
        self.percent = percent
        self.externalAC = externalAC
        self.amperageMA = amperageMA
        self.voltageMV = voltageMV
        self.upperLimit = upperLimit
        self.lowerLimit = lowerLimit
        self.chargingEnabled = chargingEnabled
        self.maintainActive = maintainActive
        self.forceDischarge = forceDischarge
        self.keyFamily = keyFamily
        self.lastError = lastError
    }

    public required init?(coder: NSCoder) {
        present = coder.decodeBool(forKey: "present")
        percent = coder.decodeInteger(forKey: "percent")
        externalAC = coder.decodeBool(forKey: "externalAC")
        amperageMA = coder.decodeDouble(forKey: "amperageMA")
        voltageMV = coder.decodeDouble(forKey: "voltageMV")
        upperLimit = coder.decodeInteger(forKey: "upperLimit")
        lowerLimit = coder.decodeInteger(forKey: "lowerLimit")
        chargingEnabled = coder.decodeBool(forKey: "chargingEnabled")
        maintainActive = coder.decodeBool(forKey: "maintainActive")
        forceDischarge = coder.decodeBool(forKey: "forceDischarge")
        keyFamily = (coder.decodeObject(of: NSString.self, forKey: "keyFamily") as String?) ?? "none"
        lastError = coder.decodeObject(of: NSString.self, forKey: "lastError") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(present, forKey: "present")
        coder.encode(percent, forKey: "percent")
        coder.encode(externalAC, forKey: "externalAC")
        coder.encode(amperageMA, forKey: "amperageMA")
        coder.encode(voltageMV, forKey: "voltageMV")
        coder.encode(upperLimit, forKey: "upperLimit")
        coder.encode(lowerLimit, forKey: "lowerLimit")
        coder.encode(chargingEnabled, forKey: "chargingEnabled")
        coder.encode(maintainActive, forKey: "maintainActive")
        coder.encode(forceDischarge, forKey: "forceDischarge")
        coder.encode(keyFamily as NSString, forKey: "keyFamily")
        coder.encode(lastError as NSString?, forKey: "lastError")
    }
}
