import SwiftUI

struct DashboardBatteryView: View {
    @EnvironmentObject private var battery: BatteryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            metrics
            HStack(alignment: .top, spacing: 20) {
                PanelCard(
                    title: L10n.t("battery"),
                    symbol: "battery.100.bolt",
                    tint: TCTheme.battery,
                    subtitle: battery.chargeStatusLabel
                ) {
                    BatteryPanel(compact: false, section: .visual)
                }
                PanelCard(
                    title: L10n.t("battery.limit"),
                    symbol: "shield.lefthalf.filled",
                    tint: TCTheme.charge,
                    subtitle: battery.chargeMode == .full ? L10n.t("battery.full") : L10n.t("battery.limit")
                ) {
                    BatteryPanel(compact: false, section: .controls)
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: DS.Space.m) {
            MetricTile(
                title: L10n.t("battery"),
                value: battery.showBattery ? "\(battery.batteryPercent)%" : "—",
                symbol: "battery.100",
                tint: TCTheme.battery,
                footnote: battery.chargeStatusLabel
            )
            MetricTile(
                title: L10n.t("battery.voltage"),
                value: battery.voltageMV > 0 ? String(format: "%.2f V", battery.voltageMV / 1000) : "—",
                symbol: "bolt.badge.clock",
                tint: TCTheme.charge,
                footnote: L10n.t("battery.current", battery.amperageMA / 1000)
            )
            MetricTile(
                title: L10n.t("metric.power"),
                value: DashboardMetrics.powerMetric(battery),
                symbol: "powerplug.fill",
                tint: TCTheme.power,
                footnote: powerSource
            )
            MetricTile(
                title: L10n.t("battery.limit"),
                value: "\(battery.chargeUpper)%",
                symbol: "shield.lefthalf.filled",
                tint: battery.maintainActive ? TCTheme.charge : TCTheme.secondaryLabel,
                footnote: L10n.t("battery.resume.value", battery.chargeLower)
            )
        }
    }

    private var powerSource: String {
        if !battery.externalAC { return L10n.t("power.battery") }
        if battery.adapterWatts > 0 { return L10n.t("power.adapter", battery.adapterWatts) }
        return L10n.t("power.ac.connected")
    }
}
