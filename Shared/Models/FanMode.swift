import Foundation

@objc public enum FanMode: Int, Codable, Sendable {
    case system = 0
    case quiet = 1
    case max = 2
    case manual = 3
}
