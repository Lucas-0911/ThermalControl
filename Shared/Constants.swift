import Foundation

public enum TC {
    public static let appBundleID = "com.thermalcontrol.app"
    public static let helperBundleID = "com.thermalcontrol.helper"
    public static let machServiceName = "com.thermalcontrol.helper"
    public static let helperPlistName = "com.thermalcontrol.helper.plist"
    public static let helperVersion = "1.2.2"
    public static let protocolVersion = 2
    /// Derived from `SMCKey` (single source of truth) — rawValues must stay
    /// byte-identical to the hardware keys.
    public static let tempKeys = SMCKey.tempKeys.map(\.rawValue)

    public static let heartbeatInterval: TimeInterval = 5
    public static let heartbeatTimeout: TimeInterval = 45
    public static let uiPollInterval: TimeInterval = 3
    public static let batteryTickInterval: TimeInterval = 2
    public static let powerSampleInterval: TimeInterval = 1
    public static let powerHistoryWindow: TimeInterval = 30

    public static let thermalCeiling: Double = 100
    public static let thermalCap: Double = 105
    public static let thermalHotspotCap: Double = 110
    public static let thermalHold: TimeInterval = 8

    public static let ftstYield: TimeInterval = 0.4
    public static let modeRetry = 12
    public static let modeRetrySleep: TimeInterval = 0.05
    public static let writeSettle: TimeInterval = 0.25

    public static let chargeTruthMA: Double = 20

    /// Charge-inhibit byte values used by `BatteryController.writeGate` —
    /// reverse-engineered on legacy CH0B/CH0C hardware. First attempt writes
    /// the HIGH byte, then falls back to LOW if charging current persists.
    public static let chargeInhibitByteHigh: UInt8 = 0x02
    public static let chargeInhibitByteLow: UInt8 = 0x01
}
