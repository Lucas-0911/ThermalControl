import Foundation

@objc(TCTempReading)
public final class TempReading: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public var key: String
    @objc public var celsius: Double

    public init(key: String, celsius: Double) {
        self.key = key
        self.celsius = celsius
    }

    public required init?(coder: NSCoder) {
        key = (coder.decodeObject(of: NSString.self, forKey: "key") as String?) ?? ""
        celsius = coder.decodeDouble(forKey: "celsius")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(key as NSString, forKey: "key")
        coder.encode(celsius, forKey: "celsius")
    }
}
