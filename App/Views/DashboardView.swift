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
        case .fans: return L10n.t("fan")
        case .battery: return L10n.t("battery")
        case .sensors: return L10n.t("temp")
        case .settings: return L10n.t("settings")
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return L10n.t("nav.overview.sub")
        case .fans: return L10n.t("nav.fans.sub")
        case .battery: return L10n.t("nav.battery.sub")
        case .sensors: return L10n.t("nav.sensors.sub")
        case .settings: return L10n.t("nav.settings.sub")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .fans: return "fanblades.fill"
        case .battery: return "battery.100.bolt"
        case .sensors: return "thermometer.medium"
        case .settings: return "gearshape.fill"
        }
    }

    var tint: Color {
        switch self {
        case .overview: return TCTheme.accent
        case .fans: return TCTheme.fan
        case .battery: return TCTheme.battery
        case .sensors: return TCTheme.temperature
        case .settings: return TCTheme.quiet
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var vm: ThermalViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 880, minHeight: 620)
        .background(TCTheme.windowBackground)
        .background(DashboardVisibility(onChange: vm.setDashboardVisible))
        .onAppear {
            vm.start()
        }
        .onDisappear {
            vm.setDashboardVisible(false)
        }
    }

    private var sidebar: some View {
        List(DashboardTab.allCases, selection: $vm.selectedDashboardTab) { tab in
            NavigationLink(value: tab) {
                Label {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .medium))
                } icon: {
                    Image(systemName: tab.icon)
                        .foregroundStyle(tab.tint)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: DS.Space.s) {
                Divider()
                HStack(spacing: DS.Space.s) {
                    ConnectionDot(connected: vm.connectionState == .connected)
                    Spacer()
                    Text(HelperStatusRow.serviceLabel(vm.smAppServiceState))
                        .font(.system(size: 10))
                        .foregroundStyle(TCTheme.tertiaryLabel)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    selectedContent
                    if let error = vm.lastError, !error.isEmpty {
                        errorBanner(error)
                    }
                }
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch vm.selectedDashboardTab {
        case .overview: DashboardOverviewView()
        case .fans: DashboardFansView()
        case .battery: DashboardBatteryView()
        case .sensors: DashboardSensorsView()
        case .settings: DashboardSettingsView()
        }
    }

    private var topBar: some View {
        HStack(spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.selectedDashboardTab.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(TCTheme.label)
                Text(vm.selectedDashboardTab.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(TCTheme.secondaryLabel)
            }
            Spacer()
            if vm.connectionState != .connected {
                HStack(spacing: 6) {
                    if vm.connectionState == .connecting || vm.connectionState == .restoring {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(vm.helperStatusText)
                        .font(.caption)
                        .foregroundStyle(TCTheme.secondaryLabel)
                }
            }
            Button(action: vm.refresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .help(L10n.t("reload"))
            .accessibilityLabel(L10n.t("reload"))

            Button(L10n.t("reset"), action: vm.confirmRestoreSystem)
                .buttonStyle(.bordered)
                .disabled(!vm.controlsEnabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TCTheme.danger)
            Text(error)
                .font(.callout.weight(.medium))
                .foregroundStyle(TCTheme.danger)
            Spacer()
            if vm.failedRestoreComponents != 0 {
                Button(L10n.t("retry"), action: vm.retryFailedRestore)
                    .buttonStyle(.bordered)
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TCTheme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
