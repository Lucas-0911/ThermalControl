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
    @objc public var canControlCharge: Bool
    @objc public var canForceDischarge: Bool
    @objc public var dischargeTargetPercent: Int
    @objc public var dischargeRemainingSeconds: TimeInterval
    @objc public var dischargeStopVerified: Bool
    @objc public var dischargeStopReason: String?

    public init(
        present: Bool, percent: Int, externalAC: Bool, amperageMA: Double, voltageMV: Double,
        upperLimit: Int, lowerLimit: Int, chargingEnabled: Bool, maintainActive: Bool,
        forceDischarge: Bool, keyFamily: String, lastError: String? = nil,
        canControlCharge: Bool = false, canForceDischarge: Bool = false,
        dischargeTargetPercent: Int = -1, dischargeRemainingSeconds: TimeInterval = 0,
        dischargeStopVerified: Bool = false, dischargeStopReason: String? = nil
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
        self.canControlCharge = canControlCharge
        self.canForceDischarge = canForceDischarge
        self.dischargeTargetPercent = dischargeTargetPercent
        self.dischargeRemainingSeconds = dischargeRemainingSeconds
        self.dischargeStopVerified = dischargeStopVerified
        self.dischargeStopReason = dischargeStopReason
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
        canControlCharge = coder.decodeBool(forKey: "canControlCharge")
        canForceDischarge = coder.decodeBool(forKey: "canForceDischarge")
        dischargeTargetPercent = coder.containsValue(forKey: "dischargeTargetPercent")
            ? coder.decodeInteger(forKey: "dischargeTargetPercent") : -1
        dischargeRemainingSeconds = coder.decodeDouble(forKey: "dischargeRemainingSeconds")
        dischargeStopVerified = coder.decodeBool(forKey: "dischargeStopVerified")
        dischargeStopReason = coder.decodeObject(of: NSString.self, forKey: "dischargeStopReason") as String?
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
        coder.encode(canControlCharge, forKey: "canControlCharge")
        coder.encode(canForceDischarge, forKey: "canForceDischarge")
        coder.encode(dischargeTargetPercent, forKey: "dischargeTargetPercent")
        coder.encode(dischargeRemainingSeconds, forKey: "dischargeRemainingSeconds")
        coder.encode(dischargeStopVerified, forKey: "dischargeStopVerified")
        coder.encode(dischargeStopReason as NSString?, forKey: "dischargeStopReason")
    }
}
