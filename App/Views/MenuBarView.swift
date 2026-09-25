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
            
            heroGlanceBar
            
            HelperStatusRow()

            // Fan Section Glass Card
            MiniCard {
                FanPanel(compact: true)
            }

            // Battery Section Glass Card
            if battery.showBattery {
                MiniCard {
                    BatteryPanel(compact: true)
                }
            }

            // Sensors Quick Preview Glass Card
            MiniCard {
                TempPanel(compact: true)
            }

            if let err = vm.lastError, !err.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(err)
                        .font(.caption)
                }
                .foregroundStyle(TCTheme.danger)
                .padding(.horizontal, 4)
            }
        }
        .padding(12)
        .frame(width: 350)
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(0.85)
        )
        .onAppear {
            vm.start()
            vm.setMenuVisible(true)
        }
        .onDisappear { vm.setMenuVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "fanblades.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TCTheme.fan)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.t("app.name"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TCTheme.label)
                Text(summary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TCTheme.secondaryLabel)
            }
            
            Spacer()
            
            ConnectionDot(connected: vm.connectionState == .connected)
            
            iconButton("gearshape.fill", help: L10n.t("settings")) {
                openMainWindow()
            }
            iconButton("xmark", help: L10n.t("quit")) {
                vm.quitApp()
            }
        }
        .padding(.horizontal, 2)
    }

    private var heroGlanceBar: some View {
        HStack(spacing: 6) {
            // Hot Temp Hero
            HStack(spacing: 4) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(vm.hottestTemp.map { TCTheme.tempTint($0) } ?? TCTheme.charge)
                Text(vm.hottestTemp.map { "\(Int($0.rounded()))°C" } ?? "—")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TCTheme.label)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(TCTheme.separator.opacity(0.3), lineWidth: 0.5)
            )

            // Fan Hero
            HStack(spacing: 4) {
                Image(systemName: "fanblades.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TCTheme.fan)
                Text(fan.fans.first.map { "\(Int($0.actualRPM))" } ?? "0")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TCTheme.label)
                Text("RPM")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(TCTheme.tertiaryLabel)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(TCTheme.separator.opacity(0.3), lineWidth: 0.5)
            )

            // Battery Hero
            HStack(spacing: 4) {
                Image(systemName: battery.maintainActive ? "shield.lefthalf.filled" : (battery.externalAC ? "powerplug.fill" : "battery.100"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(battery.maintainActive ? TCTheme.charge : (battery.batteryPercent <= 20 ? TCTheme.danger : TCTheme.battery))
                Text(battery.showBattery ? "\(battery.batteryPercent)%" : "AC")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(TCTheme.label)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(TCTheme.separator.opacity(0.3), lineWidth: 0.5)
            )
        }
    }

    private var summary: String {
        let fCount = fan.fans.count
        if fCount > 1 {
            return "\(fCount) \(L10n.t("fan").lowercased())"
        }
        return fan.desiredFanMode == .manual ? L10n.t("mode.custom.rpm", fan.manualRPM) : modeName
    }

    private var modeName: String {
        switch fan.desiredFanMode {
        case .system: return L10n.t("mode.auto")
        case .quiet:  return L10n.t("mode.quiet")
        case .max:    return L10n.t("mode.max")
        case .manual: return L10n.t("mode.custom")
        }
    }

    private func iconButton(_ name: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TCTheme.secondaryLabel)
                .frame(width: 24, height: 24)
                .background(Color(nsColor: .controlColor).opacity(0.6), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func openMainWindow() {
        WindowLocator.bringDashboardForward()
        if WindowLocator.dashboardWindow() == nil {
            openWindow(id: "dashboard")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                WindowLocator.bringDashboardForward()
            }
        }
    }
}
