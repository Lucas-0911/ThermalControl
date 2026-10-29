import Foundation

@objc(TCFanStatus)
public final class FanStatus: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public var fans: [FanChannel]
    @objc public var desiredMode: Int
    @objc public var ftstPresent: Bool
    @objc public var lastError: String?
    @objc public var ramping: Bool
    @objc public var transitionID: Int

    public init(fans: [FanChannel], desiredMode: Int, ftstPresent: Bool, lastError: String? = nil, ramping: Bool = false, transitionID: Int = 0) {
        self.fans = fans
        self.desiredMode = desiredMode
        self.ftstPresent = ftstPresent
        self.lastError = lastError
        self.ramping = ramping
        self.transitionID = transitionID
    }

    public required init?(coder: NSCoder) {
        fans = coder.decodeArrayOfObjects(ofClass: FanChannel.self, forKey: "fans") ?? []
        desiredMode = coder.decodeInteger(forKey: "desiredMode")
        ftstPresent = coder.decodeBool(forKey: "ftstPresent")
        ramping = coder.decodeBool(forKey: "ramping")
        transitionID = coder.decodeInteger(forKey: "transitionID")
        lastError = coder.decodeObject(of: NSString.self, forKey: "lastError") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(fans as NSArray, forKey: "fans")
        coder.encode(desiredMode, forKey: "desiredMode")
        coder.encode(ftstPresent, forKey: "ftstPresent")
        coder.encode(ramping, forKey: "ramping")
        coder.encode(transitionID, forKey: "transitionID")
        coder.encode(lastError as NSString?, forKey: "lastError")
    }
}
