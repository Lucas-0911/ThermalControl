import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var fan: FanViewModel
    @EnvironmentObject var battery: BatteryViewModel
    @EnvironmentObject var lang: LanguageSettings

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    metrics
                    PanelCard(title: L10n.t("fan"), symbol: "fanblades.fill", tint: TCTheme.fan) {
                        FanPanel(compact: false)
                    }
                    HStack(alignment: .top, spacing: DS.Space.l) {
                        PanelCard(title: L10n.t("battery"), symbol: "battery.100.bolt", tint: TCTheme.battery) {
                            BatteryPanel(compact: false)
                        }
                        PanelCard(title: L10n.t("temp.hot"), symbol: "thermometer.medium", tint: TCTheme.temperature) {
                            TempPanel(compact: false)
                        }
                    }
                    PanelCard(title: L10n.t("helper"), symbol: "bolt.shield.fill", tint: TCTheme.quiet) {
                        HelperStatusRow(detailed: true)
                        Text(L10n.t("helper.hint"))
                            .font(.caption)
                            .foregroundStyle(TCTheme.secondaryLabel)
                    }
                    if let err = vm.lastError, !err.isEmpty {
                        Text(err)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(TCTheme.danger)
                    }
                }
                .padding(DS.Space.xl)
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        .background(TCTheme.windowBackground)
        .onAppear {
            vm.start()
            vm.setDashboardVisible(true)
        }
        .onDisappear { vm.setDashboardVisible(false) }
    }

    private var toolbar: some View {
        HStack(spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(L10n.t("app.name"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(TCTheme.label)
                Text(vm.helperStatusText)
                    .font(.caption)
                    .foregroundStyle(TCTheme.secondaryLabel)
            }
            Spacer()
            ConnectionDot(connected: vm.connectionState == .connected)
            Picker(L10n.t("language"), selection: $lang.selection) {
                Text(L10n.t("language.system")).tag("system")
                Text("English").tag("en")
                Text("Tiếng Việt").tag("vi")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 130)
            Toggle(L10n.t("login.start"), isOn: Binding(
                get: { vm.startAtLogin },
                set: { vm.setStartAtLogin($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            Button(L10n.t("reset")) { vm.restoreSystem() }
                .buttonStyle(.bordered)
                .disabled(!vm.controlsEnabled)
            Button(L10n.t("reload")) { vm.refresh() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.m + 2)
        .background(.bar)
    }

    private var metrics: some View {
        HStack(spacing: DS.Space.m) {
            MetricTile(
                title: L10n.t("fan"),
                value: fanMetric,
                symbol: "fanblades.fill",
                tint: TCTheme.fan,
                footnote: fan.desiredFanMode == .manual ? L10n.t("mode.custom.rpm", fan.manualRPM) : modeName
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
                value: powerMetric,
                symbol: "bolt.fill",
                tint: TCTheme.power,
                footnote: battery.externalAC
                    ? (battery.adapterWatts > 0 ? L10n.t("power.adapter", battery.adapterWatts) : L10n.t("power.plugged"))
                    : L10n.t("power.on.battery")
            )
            MetricTile(
                title: L10n.t("temp"),
                value: vm.hottestTemp.map { "\(Int($0.rounded()))°" } ?? "—",
                symbol: "thermometer.medium",
                tint: TCTheme.temperature,
                footnote: L10n.t("temp.sensors", vm.temps.count)
            )
        }
    }

    private var fanMetric: String {
        guard let rpm = fan.fans.first?.actualRPM, rpm > 0 else { return "—" }
        return "\(Int(rpm))"
    }

    private var modeName: String {
        switch fan.desiredFanMode {
        case .system: return L10n.t("mode.auto")
        case .quiet: return L10n.t("mode.quiet")
        case .max: return L10n.t("mode.max")
        case .manual: return L10n.t("mode.custom")
        }
    }

    private var powerMetric: String {
        if battery.systemInWatts >= 0.3 {
            return String(format: "%.0fW", battery.systemInWatts)
        }
        if battery.externalAC, battery.adapterWatts > 0 {
            return String(format: "%.0fW", battery.adapterWatts)
        }
        return battery.externalAC ? "AC" : "—"
    }
}
