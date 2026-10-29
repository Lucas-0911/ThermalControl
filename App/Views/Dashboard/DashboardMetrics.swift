import Foundation

@MainActor
enum DashboardMetrics {
    static func fanModeName(_ mode: FanMode) -> String {
        switch mode {
        case .system: return L10n.t("mode.auto")
        case .quiet: return L10n.t("mode.quiet")
        case .max: return L10n.t("mode.max")
        case .manual: return L10n.t("mode.custom")
        }
    }

    static func fanMetric(_ fan: FanViewModel) -> String {
        guard fan.showFan else { return "—" }
        if fan.fans.count > 1 {
            return fan.fans
                .map { String(Int($0.actualRPM.rounded())) }
                .joined(separator: " / ")
        }
        return String(Int(fan.fans.first?.actualRPM.rounded() ?? 0))
    }

    static func powerMetric(_ battery: BatteryViewModel) -> String {
        if battery.externalAC {
            if battery.systemInWatts >= 0.3 {
                return String(format: "%.0fW", battery.systemInWatts)
            }
            if battery.adapterWatts > 0 {
                return String(format: "%.0fW", battery.adapterWatts)
            }
            return L10n.t("power.plugged")
        }
        return battery.usageWatts > 0.5 ? String(format: "%.0fW", battery.usageWatts) : "—"
    }
}
