import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var fan: FanViewModel
    @EnvironmentObject var battery: BatteryViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s + 2) {
            header
            HelperStatusRow()
            MiniCard {
                FanPanel(compact: true)
            }
            MiniCard {
                BatteryPanel(compact: true)
            }
            if let err = vm.lastError, !err.isEmpty {
                Text(err)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TCTheme.danger)
            }
        }
        .padding(DS.Space.m + 2)
        .frame(width: 360)
        .onAppear { vm.start() }
    }

    private var header: some View {
        HStack(spacing: DS.Space.s) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(L10n.t("app.name"))
                    .font(.headline)
                    .foregroundStyle(TCTheme.label)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(TCTheme.secondaryLabel)
            }
            Spacer()
            ConnectionDot(connected: vm.connectionState == .connected)
            iconButton("gearshape", help: L10n.t("settings")) {
                openMainWindow()
            }
            iconButton("xmark", help: L10n.t("quit")) {
                vm.quitApp()
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(TCTheme.secondaryLabel)
                .frame(width: DS.Icon.button, height: DS.Icon.button)
                .background(TCTheme.controlFill, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var summary: String {
        var parts: [String] = []
        if let t = vm.hottestTemp { parts.append("\(Int(t.rounded()))°") }
        if let rpm = fan.fans.first?.actualRPM, rpm > 0 { parts.append("\(Int(rpm)) RPM") }
        if battery.showBattery { parts.append("\(battery.batteryPercent)%") }
        return parts.isEmpty ? vm.helperStatusText : parts.joined(separator: "  ·  ")
    }

    private func openMainWindow() {
        dismiss()
        if let existing = WindowLocator.dashboardWindow() {
            WindowLocator.bringDashboardForward()
            _ = existing // bringDashboardForward already orders it front
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
