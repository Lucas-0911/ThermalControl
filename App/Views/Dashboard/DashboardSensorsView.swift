import SwiftUI

struct DashboardSensorsView: View {
    @EnvironmentObject private var vm: ThermalViewModel
    @EnvironmentObject private var fan: FanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            metrics
            HStack(alignment: .top, spacing: 20) {
                PanelCard(
                    title: L10n.t("temp.processor"),
                    symbol: "cpu",
                    tint: TCTheme.temperature,
                    subtitle: L10n.t("temp.processor.subtitle")
                ) {
                    TempPanel(compact: false, section: .processor)
                }
                PanelCard(
                    title: L10n.t("temp.system"),
                    symbol: "macbook.and.iphone",
                    tint: TCTheme.quiet,
                    subtitle: L10n.t("temp.system.subtitle")
                ) {
                    TempPanel(compact: false, section: .system)
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: DS.Space.m) {
            MetricTile(
                title: L10n.t("temp.hotspot"),
                value: vm.hottestTemp.map { "\(Int($0.rounded()))°C" } ?? "—",
                symbol: "flame.fill",
                tint: TCTheme.danger,
                footnote: L10n.t("temp.highest")
            )
            MetricTile(
                title: L10n.t("temp.average"),
                value: averageTemperature,
                symbol: "thermometer.medium",
                tint: TCTheme.temperature,
                footnote: L10n.t("temp.system.average")
            )
            MetricTile(
                title: L10n.t("temp.sensor.count"),
                value: "\(vm.temps.count)",
                symbol: "cpu",
                tint: TCTheme.quiet,
                footnote: L10n.t("temp.telemetry.active")
            )
            MetricTile(
                title: L10n.t("fan.cooling"),
                value: DashboardMetrics.fanMetric(fan),
                symbol: "fanblades.fill",
                tint: TCTheme.fan,
                footnote: DashboardMetrics.fanModeName(fan.desiredFanMode)
            )
        }
    }

    private var averageTemperature: String {
        guard !vm.temps.isEmpty else { return "—" }
        let average = vm.temps.map(\.celsius).reduce(0, +) / Double(vm.temps.count)
        return "\(Int(average.rounded()))°C"
    }
}
