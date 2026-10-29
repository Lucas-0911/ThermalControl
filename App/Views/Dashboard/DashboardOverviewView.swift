import SwiftUI

struct DashboardOverviewView: View {
    @EnvironmentObject private var vm: ThermalViewModel
    @EnvironmentObject private var fan: FanViewModel
    @EnvironmentObject private var battery: BatteryViewModel
    @EnvironmentObject private var power: PowerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            metrics
            HStack(alignment: .top, spacing: 20) {
                PanelCard(
                    title: L10n.t("fan"),
                    symbol: "fanblades.fill",
                    tint: TCTheme.fan,
                    subtitle: fan.desiredFanMode == .manual
                        ? L10n.t("mode.custom.rpm", fan.manualRPM)
                        : DashboardMetrics.fanModeName(fan.desiredFanMode)
                ) {
                    FanPanel(compact: false, allowsEditing: false)
                }
                if battery.showBattery {
                    PanelCard(
                        title: L10n.t("battery"),
                        symbol: "battery.100.bolt",
                        tint: TCTheme.battery,
                        subtitle: battery.chargeStatusLabel
                    ) {
                        BatteryPanel(compact: false, allowsEditing: false)
                    }
                }
            }
            PanelCard(
                title: L10n.t("power.chart"),
                symbol: "waveform.path.ecg",
                tint: TCTheme.power,
                subtitle: L10n.t("power.history.subtitle")
            ) {
                HStack(spacing: DS.Space.m) {
                    PowerSparkline(
                        samples: power.powerHistory,
                        maxWatts: power.powerChartMax,
                        compact: false,
                        title: L10n.t("power.chart"),
                        tint: TCTheme.power
                    )
                    PowerSparkline(
                        samples: power.usageHistory,
                        maxWatts: power.usageChartMax,
                        compact: false,
                        title: L10n.t("usage.chart"),
                        tint: TCTheme.temperature
                    )
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: DS.Space.m) {
            MetricTile(
                title: L10n.t("fan"),
                value: DashboardMetrics.fanMetric(fan),
                symbol: "fanblades.fill",
                tint: TCTheme.fan,
                footnote: fan.desiredFanMode == .manual
                    ? L10n.t("mode.custom.rpm", fan.manualRPM)
                    : DashboardMetrics.fanModeName(fan.desiredFanMode)
            )
            MetricTile(
                title: L10n.t("battery"),
                value: battery.showBattery ? "\(battery.batteryPercent)%" : "—",
                symbol: "battery.100",
                tint: TCTheme.battery,
                footnote: battery.showBattery ? battery.chargeStatusLabel : L10n.t("no.battery")
            )
            MetricTile(
                title: L10n.t("metric.power"),
                value: DashboardMetrics.powerMetric(battery),
                symbol: "bolt.fill",
                tint: TCTheme.power,
                footnote: battery.externalAC
                    ? (battery.adapterWatts > 0 ? L10n.t("power.adapter", battery.adapterWatts) : L10n.t("power.plugged"))
                    : L10n.t("power.on.battery")
            )
            MetricTile(
                title: L10n.t("temp"),
                value: vm.hottestTemp.map { "\(Int($0.rounded()))°C" } ?? "—",
                symbol: "thermometer.medium",
                tint: TCTheme.temperature,
                footnote: L10n.t("temp.sensors", vm.temps.count)
            )
        }
    }
}
