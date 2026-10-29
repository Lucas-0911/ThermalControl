import AppKit

extension ThermalViewModel {
    var hottestTemp: Double? { temps.map(\.celsius).max() }

    var menuTitle: String {
        if connectionState != .connected { return "TC" }
        if let rpm = fan.fans.first?.actualRPM, rpm > 0 { return "\(Int(rpm))" }
        if battery.batteryPresent { return "\(battery.batteryPercent)%" }
        return "TC"
    }

    var menuSymbol: String {
        if connectionState == .connected, fan.fans.isEmpty, battery.batteryPresent { return "battery.75" }
        return "fan"
    }
}
