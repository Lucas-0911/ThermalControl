import Foundation

@objc(TCFanChannel)
public final class FanChannel: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public var index: Int
    @objc public var actualRPM: Double
    @objc public var targetRPM: Double
    @objc public var minRPM: Double
    @objc public var maxRPM: Double
    @objc public var modeRaw: Int
    @objc public var modeKey: String

    public init(index: Int, actualRPM: Double, targetRPM: Double, minRPM: Double, maxRPM: Double, modeRaw: Int, modeKey: String) {
        self.index = index
        self.actualRPM = actualRPM
        self.targetRPM = targetRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.modeRaw = modeRaw
        self.modeKey = modeKey
    }

    public required init?(coder: NSCoder) {
        index = coder.decodeInteger(forKey: "index")
        actualRPM = coder.decodeDouble(forKey: "actualRPM")
        targetRPM = coder.decodeDouble(forKey: "targetRPM")
        minRPM = coder.decodeDouble(forKey: "minRPM")
        maxRPM = coder.decodeDouble(forKey: "maxRPM")
        modeRaw = coder.decodeInteger(forKey: "modeRaw")
        modeKey = (coder.decodeObject(of: NSString.self, forKey: "modeKey") as String?) ?? "F0Md"
    }

    public func encode(with coder: NSCoder) {
        coder.encode(index, forKey: "index")
        coder.encode(actualRPM, forKey: "actualRPM")
        coder.encode(targetRPM, forKey: "targetRPM")
        coder.encode(minRPM, forKey: "minRPM")
        coder.encode(maxRPM, forKey: "maxRPM")
        coder.encode(modeRaw, forKey: "modeRaw")
        coder.encode(modeKey as NSString, forKey: "modeKey")
    }
}
