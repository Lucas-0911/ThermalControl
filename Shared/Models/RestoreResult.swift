import Foundation

/// Per-component outcomes; nil means that component was not requested.
@objc(RestoreResult)
public final class RestoreResult: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }
    public let fanError: String?
    public let chargeError: String?
    public let dischargeError: String?
    public let attempted: Int

    public static let fan = 1
    public static let charge = 2
    public static let discharge = 4
    public static let transient = fan | discharge
    public static let all = fan | charge | discharge

    public init(attempted: Int, fanError: String? = nil, chargeError: String? = nil, dischargeError: String? = nil) {
        self.attempted = attempted
        self.fanError = fanError
        self.chargeError = chargeError
        self.dischargeError = dischargeError
    }

    public var succeeded: Bool { failedComponents == 0 }
    public var failedComponents: Int {
        (fanError == nil ? 0 : Self.fan) |
        (chargeError == nil ? 0 : Self.charge) |
        (dischargeError == nil ? 0 : Self.discharge)
    }
    public var message: String? {
        let errors = [fanError, chargeError, dischargeError].compactMap { $0 }
        return errors.isEmpty ? nil : errors.joined(separator: "; ")
    }

    public required init?(coder: NSCoder) {
        attempted = coder.decodeInteger(forKey: "attempted")
        guard attempted > 0, attempted & ~Self.all == 0 else { return nil }
        fanError = coder.decodeObject(of: NSString.self, forKey: "fanError") as String?
        chargeError = coder.decodeObject(of: NSString.self, forKey: "chargeError") as String?
        dischargeError = coder.decodeObject(of: NSString.self, forKey: "dischargeError") as String?
    }

    public func encode(with coder: NSCoder) {
        coder.encode(attempted, forKey: "attempted")
        coder.encode(fanError, forKey: "fanError")
        coder.encode(chargeError, forKey: "chargeError")
        coder.encode(dischargeError, forKey: "dischargeError")
    }
}
