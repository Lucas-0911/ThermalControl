import Foundation

/// Which SMC charge-inhibit key family the machine exposes.
/// `rawValue` is surfaced to the app through `Capabilities.batteryFamily`.
enum BatteryFamily: String {
    case none
    case legacy = "CH0B/CH0C"
    case tahoe = "CHTE/CHIE"
}