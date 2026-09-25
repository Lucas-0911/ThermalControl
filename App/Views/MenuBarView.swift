import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var fan: FanViewModel
    @EnvironmentObject var battery: BatteryViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            
            heroGlanceBar
            
            HelperStatusRow()

            // Fan Section
            MiniCard {
                FanPanel(compact: true)
            }

            // Battery Section
            if battery.showBattery {
                MiniCard {
                    BatteryPanel(compact: true)
                }
            }

            if let err = vm.lastError, !err.isEmpty {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(TCTheme.danger)
                    .padding(.horizontal, 4)
            }
        }
        .padding(14)
        .frame(width: 350)
        .onAppear {
            vm.start()
            vm.setMenuVisible(true)
        }
        .onDisappear { vm.setMenuVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "fanblades.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TCTheme.fan)
            
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

    private var heroGlanceBar: some View {
        HStack(spacing: 8) {
            // Hot Temp Hero
            HStack(spacing: 5) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(vm.hottestTemp.map { TCTheme.tempTint($0) } ?? TCTheme.charge)
                Text(vm.hottestTemp.map { "\(Int($0.rounded()))°C" } ?? "—")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TCTheme.label)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(TCTheme.separator.opacity(0.3), lineWidth: 0.5)
            )

            // Fan Hero
            HStack(spacing: 5) {
                Image(systemName: "fanblades.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TCTheme.fan)
                Text(fan.fans.first.map { "\(Int($0.actualRPM))" } ?? "0")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TCTheme.label)
                Text("RPM")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(TCTheme.tertiaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(TCTheme.separator.opacity(0.3), lineWidth: 0.5)
            )

            // Battery Hero
            HStack(spacing: 5) {
                Image(systemName: battery.maintainActive ? "bolt.slash.fill" : "battery.100.bolt")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(battery.maintainActive ? TCTheme.charge : TCTheme.battery)
                Text(battery.showBattery ? "\(battery.batteryPercent)%" : "—")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TCTheme.label)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(TCTheme.separator.opacity(0.3), lineWidth: 0.5)
            )
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TCTheme.secondaryLabel)
                .frame(width: 24, height: 24)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(TCTheme.separator.opacity(0.3), lineWidth: 0.5))
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
