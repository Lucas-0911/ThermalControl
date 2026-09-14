import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var fan: FanViewModel
    @EnvironmentObject var battery: BatteryViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HelperStatusRow()
            MiniCard(tint: TCTheme.cyan) {
                FanPanel(compact: true)
            }
            MiniCard(tint: TCTheme.lime) {
                BatteryPanel(compact: true)
            }
            if let err = vm.lastError, !err.isEmpty {
                Text(err).font(.caption.weight(.semibold)).foregroundStyle(TCTheme.peach)
            }
        }
        .padding(14)
        .frame(width: 360)
        .onAppear { vm.start() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("app.name"))
                    .font(.title2.weight(.heavy))
                    .fontDesign(.rounded)
                Text(summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ConnectionDot(connected: vm.connectionState == .connected)
            iconButton("gearshape.fill", tint: TCTheme.grape, help: L10n.t("settings")) {
                openMainWindow()
            }
            iconButton("xmark", tint: TCTheme.peach, help: L10n.t("quit")) {
                vm.quitApp()
            }
        }
    }

    private func iconButton(_ symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.16), in: Circle())
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
