import SwiftUI

struct DashboardFansView: View {
    @EnvironmentObject private var vm: ThermalViewModel
    @EnvironmentObject private var fan: FanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            metrics
            HStack(alignment: .top, spacing: 20) {
                PanelCard(
                    title: L10n.t("fan"),
                    symbol: "gauge.with.needle",
                    tint: TCTheme.fan,
                    subtitle: L10n.t("fan.active", fan.fans.count)
                ) {
                    FanPanel(compact: false, section: .visual)
                }
                PanelCard(
                    title: L10n.t("mode.custom"),
                    symbol: "slider.horizontal.3",
                    tint: TCTheme.power,
                    subtitle: DashboardMetrics.fanModeName(fan.desiredFanMode)
                ) {
                    FanPanel(compact: false, section: .controls)
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: DS.Space.m) {
            MetricTile(
                title: fan.fans.isEmpty ? L10n.t("fan") : L10n.t("fan.n", 1),
                value: fan.fans.isEmpty ? "—" : "\(Int(fan.fans[0].actualRPM.rounded())) RPM",
                symbol: "fanblades.fill",
                tint: TCTheme.fan,
                footnote: fan.fans.isEmpty ? nil : L10n.t("fan.target", fan.fans[0].targetRPM)
            )
            MetricTile(
                title: fan.fans.count > 1 ? L10n.t("fan.n", 2) : L10n.t("fan.n", 2),
                value: fan.fans.count > 1 ? "\(Int(fan.fans[1].actualRPM.rounded())) RPM" : "—",
                symbol: "fanblades.fill",
                tint: TCTheme.fan,
                footnote: fan.fans.count > 1
                    ? L10n.t("fan.target", fan.fans[1].targetRPM)
                    : L10n.t("fan.single")
            )
            MetricTile(
                title: L10n.t("mode"),
                value: DashboardMetrics.fanModeName(fan.desiredFanMode),
                symbol: "speedometer",
                tint: TCTheme.power,
                footnote: fan.desiredFanMode == .manual
                    ? L10n.t("mode.custom")
                    : (fan.desiredFanMode == .quiet ? L10n.t("mode.quiet.hint")
                       : (fan.desiredFanMode == .max ? L10n.t("mode.max.policy") : L10n.t("mode.automatic.policy")))
            )
            MetricTile(
                title: L10n.t("temp.hot"),
                value: vm.hottestTemp.map { "\(Int($0.rounded()))°C" } ?? "—",
                symbol: "flame.fill",
                tint: TCTheme.danger,
                footnote: L10n.t("temp.peak")
            )
        }
    }
}
