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
            
            Divider().opacity(0.6)
            
            HelperStatusRow()

            // Fan Section
            GroupBox {
                FanPanel(compact: true)
                    .padding(.vertical, 2)
            }

            // Battery Section
            if battery.showBattery {
                GroupBox {
                    BatteryPanel(compact: true)
                        .padding(.vertical, 2)
                }
            }

            if let err = vm.lastError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(TCTheme.danger)
                    .padding(.horizontal, 4)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear {
            vm.start()
            vm.setMenuVisible(true)
        }
        .onDisappear { vm.setMenuVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "fanblades.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TCTheme.secondaryLabel)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("app.name"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TCTheme.label)
                Text(summary)
                    .font(.system(size: 11))
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
        .padding(.horizontal, 2)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TCTheme.secondaryLabel)
                .frame(width: 22, height: 22)
                .background(Color(nsColor: .controlColor), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var summary: String {
        var parts: [String] = []
        if let t = vm.hottestTemp { parts.append("\(Int(t.rounded()))°") }
        if let rpm = fan.fans.first?.actualRPM, rpm > 0 { parts.append("\(Int(rpm)) RPM") }
        if battery.showBattery { parts.append("\(battery.batteryPercent)%") }
        return parts.isEmpty ? vm.helperStatusText : parts.joined(separator: " · ")
    }

    private func openMainWindow() {
        dismiss()
        if let existing = WindowLocator.dashboardWindow() {
            WindowLocator.bringDashboardForward()
            _ = existing
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
