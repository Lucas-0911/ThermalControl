import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var fan: FanViewModel
    @EnvironmentObject var battery: BatteryViewModel
    @EnvironmentObject var lang: LanguageSettings

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    TCTheme.grape.opacity(0.18),
                    TCTheme.cyan.opacity(0.10),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                toolbar
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        metrics
                        PanelCard(title: L10n.t("fan"), symbol: "fanblades.fill", tint: TCTheme.cyan) {
                            FanPanel(compact: false)
                        }
                        HStack(alignment: .top, spacing: 16) {
                            PanelCard(title: L10n.t("battery"), symbol: "battery.100.bolt", tint: TCTheme.lime) {
                                BatteryPanel(compact: false)
                            }
                            PanelCard(title: L10n.t("temp.hot"), symbol: "thermometer.medium", tint: TCTheme.peach) {
                                TempPanel(compact: false)
                            }
                        }
                        PanelCard(title: L10n.t("helper"), symbol: "bolt.shield.fill", tint: TCTheme.grape) {
                            HelperStatusRow(detailed: true)
                            Text(L10n.t("helper.hint"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let err = vm.lastError, !err.isEmpty {
                            Text(err)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(TCTheme.peach)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        .onAppear { vm.start() }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("app.name"))
                    .font(.largeTitle.weight(.heavy))
                    .fontDesign(.rounded)
                Text(vm.helperStatusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ConnectionDot(connected: vm.connectionState == .connected)
            Picker(L10n.t("language"), selection: $lang.selection) {
                Text(L10n.t("language.system")).tag("system")
                Text("English").tag("en")
                Text("Tiếng Việt").tag("vi")
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            Toggle(L10n.t("login.start"), isOn: Binding(
                get: { vm.startAtLogin },
                set: { vm.setStartAtLogin($0) }
            ))
            .toggleStyle(.switch)
            Button(L10n.t("reset")) { vm.restoreSystem() }
                .buttonStyle(.bordered)
                .disabled(!vm.controlsEnabled)
            Button(L10n.t("reload")) { vm.refresh() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            MetricTile(
                title: L10n.t("fan"),
                value: fanMetric,
                symbol: "fanblades.fill",
                tint: TCTheme.cyan,
                footnote: fan.desiredFanMode == .manual ? L10n.t("mode.custom.rpm", fan.manualRPM) : modeName
            )
            MetricTile(
                title: L10n.t("battery"),
                value: battery.showBattery ? "\(battery.batteryPercent)%" : "—",
                symbol: "battery.100",
                tint: TCTheme.lime,
                footnote: battery.showBattery ? battery.chargeStatusLabel : L10n.t("no.battery")
            )
            MetricTile(
                title: L10n.t("metric.power"),
                value: powerMetric,
                symbol: "bolt.fill",
                tint: TCTheme.sun,
                footnote: battery.externalAC
                    ? (battery.adapterWatts > 0 ? L10n.t("power.adapter", battery.adapterWatts) : L10n.t("power.plugged"))
                    : L10n.t("power.on.battery")
            )
            MetricTile(
                title: L10n.t("temp"),
                value: vm.hottestTemp.map { "\(Int($0.rounded()))°" } ?? "—",
                symbol: "thermometer.medium",
                tint: TCTheme.peach,
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
