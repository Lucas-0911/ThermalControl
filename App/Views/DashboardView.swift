import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case fans
    case battery
    case sensors
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return L10n.t("nav.overview")
        case .fans:     return L10n.t("fan")
        case .battery:  return L10n.t("battery")
        case .sensors:  return L10n.t("temp")
        case .settings: return L10n.t("settings")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .fans:     return "fanblades.fill"
        case .battery:  return "battery.100.bolt"
        case .sensors:  return "thermometer.medium"
        case .settings: return "gearshape.fill"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var fan: FanViewModel
    @EnvironmentObject var battery: BatteryViewModel
    @EnvironmentObject var power: PowerViewModel
    @EnvironmentObject var lang: LanguageSettings

    @State private var selectedTab: DashboardTab = .overview

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .frame(minWidth: 880, minHeight: 620)
        .background(TCTheme.windowBackground)
        .onAppear {
            vm.start()
            vm.setDashboardVisible(true)
        }
        .onDisappear {
            vm.setDashboardVisible(false)
        }
    }

    // MARK: - Sidebar
    private var sidebar: some View {
        List(DashboardTab.allCases, selection: $selectedTab) { tab in
            NavigationLink(value: tab) {
                Label {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .medium))
                } icon: {
                    Image(systemName: tab.icon)
                        .foregroundStyle(tabColor(for: tab))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                ConnectionDot(connected: vm.connectionState == .connected)
                Spacer()
                Text(vm.smAppServiceState)
                    .font(.system(size: 10))
                    .foregroundStyle(TCTheme.tertiaryLabel)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Detail Content Router
    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .overview:
                        overviewView
                    case .fans:
                        fansView
                    case .battery:
                        batteryView
                    case .sensors:
                        sensorsView
                    case .settings:
                        settingsView
                    }

                    if let err = vm.lastError, !err.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(TCTheme.danger)
                            Text(err)
                                .font(.callout.weight(.medium))
                                .foregroundStyle(TCTheme.danger)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(TCTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(24)
            }
        }
    }

    // MARK: - Unified Header Toolbar
    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedTab.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(TCTheme.label)
                Text(topBarSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(TCTheme.secondaryLabel)
            }

            Spacer()

            Button(action: { vm.refresh() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .help(L10n.t("reload"))

            Button(L10n.t("reset")) {
                vm.restoreSystem()
            }
            .buttonStyle(.bordered)
            .disabled(!vm.controlsEnabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var topBarSubtitle: String {
        switch selectedTab {
        case .overview: return L10n.t("nav.overview.sub")
        case .fans:     return L10n.t("nav.fans.sub")
        case .battery:  return L10n.t("nav.battery.sub")
        case .sensors:  return L10n.t("temp.sensors", vm.temps.count)
        case .settings: return vm.helperStatusText
        }
    }

    // MARK: - Tab 1: Overview
    private var overviewView: some View {
        VStack(alignment: .leading, spacing: 20) {
            metricsGrid

            HStack(alignment: .top, spacing: 20) {
                PanelCard(title: L10n.t("fan"), symbol: "fanblades.fill", tint: TCTheme.fan, subtitle: fan.desiredFanMode == .manual ? L10n.t("mode.custom.rpm", fan.manualRPM) : modeName) {
                    FanPanel(compact: false)
                }

                if battery.showBattery {
                    PanelCard(title: L10n.t("battery"), symbol: "battery.100.bolt", tint: TCTheme.battery, subtitle: battery.chargeStatusLabel) {
                        BatteryPanel(compact: false)
                    }
                }
            }

            PanelCard(title: L10n.t("power.chart"), symbol: "waveform.path.ecg", tint: TCTheme.power, subtitle: "30s rolling power history") {
                PowerSparkline(
                    samples: power.powerHistory,
                    maxWatts: power.powerChartMax,
                    compact: false,
                    title: L10n.t("power.chart"),
                    tint: TCTheme.power
                )
            }
        }
    }

    // MARK: - Tab 2: Fans Detail
    private var fansView: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelCard(title: L10n.t("fan"), symbol: "fanblades.fill", tint: TCTheme.fan) {
                FanPanel(compact: false)
            }
        }
    }

    // MARK: - Tab 3: Battery Detail
    private var batteryView: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelCard(title: L10n.t("battery"), symbol: "battery.100.bolt", tint: TCTheme.battery) {
                BatteryPanel(compact: false)
            }
        }
    }

    // MARK: - Tab 4: Sensors Telemetry
    private var sensorsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelCard(title: L10n.t("temp"), symbol: "thermometer.medium", tint: TCTheme.temperature, subtitle: L10n.t("temp.sensors", vm.temps.count)) {
                TempPanel(compact: false)
            }
        }
    }

    // MARK: - Tab 5: Settings & Helper
    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            PanelCard(title: L10n.t("settings"), symbol: "gearshape.fill", tint: TCTheme.accent) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(L10n.t("language"))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: $lang.selection) {
                            Text(L10n.t("language.system")).tag("system")
                            Text("English").tag("en")
                            Text("Tiếng Việt").tag("vi")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 140)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.t("login.start"))
                                .font(.system(size: 13, weight: .medium))
                            Text("Tự động mở ứng dụng trên Menu Bar khi đăng nhập")
                                .font(.caption)
                                .foregroundStyle(TCTheme.secondaryLabel)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { vm.startAtLogin },
                            set: { vm.setStartAtLogin($0) }
                        ))
                        .toggleStyle(.switch)
                    }
                }
            }

            PanelCard(title: L10n.t("helper"), symbol: "shield.lefthalf.filled", tint: TCTheme.quiet) {
                HelperStatusRow(detailed: true)
                Text(L10n.t("helper.hint"))
                    .font(.caption)
                    .foregroundStyle(TCTheme.secondaryLabel)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Metrics Row
    private var metricsGrid: some View {
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
                value: vm.hottestTemp.map { "\(Int($0.rounded()))°C" } ?? "—",
                symbol: "thermometer.medium",
                tint: TCTheme.temperature,
                footnote: L10n.t("temp.sensors", vm.temps.count)
            )
        }
    }

    // MARK: - Helpers
    private func tabColor(for tab: DashboardTab) -> Color {
        switch tab {
        case .overview: return TCTheme.accent
        case .fans:     return TCTheme.fan
        case .battery:  return TCTheme.battery
        case .sensors:  return TCTheme.temperature
        case .settings: return TCTheme.quiet
        }
    }

    private var fanMetric: String {
        guard fan.showFan else { return "—" }
        if fan.fans.count > 1 {
            let rpms = fan.fans.map { "\(Int($0.actualRPM.rounded()))" }
            return rpms.joined(separator: " / ")
        }
        return "\(Int(fan.fans.first?.actualRPM.rounded() ?? 0))"
    }

    private var powerMetric: String {
        if battery.externalAC {
            if battery.systemInWatts >= 0.3 {
                return String(format: "%.0fW", battery.systemInWatts)
            }
            if battery.adapterWatts > 0 {
                return String(format: "%.0fW", battery.adapterWatts)
            }
            return L10n.t("power.plugged")
        }
        let u = battery.usageWatts
        return u > 0.5 ? String(format: "%.0fW", u) : "—"
    }

    private var modeName: String {
        switch fan.desiredFanMode {
        case .system: return L10n.t("mode.auto")
        case .quiet:  return L10n.t("mode.quiet")
        case .max:    return L10n.t("mode.max")
        case .manual: return L10n.t("mode.custom")
        }
    }
}
