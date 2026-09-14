import SwiftUI

struct BatteryPanel: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var battery: BatteryViewModel
    @EnvironmentObject var power: PowerViewModel
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if compact {
                Label(L10n.t("battery"), systemImage: "battery.100.bolt")
                    .font(.headline.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(TCTheme.lime)
            }
            if !battery.showBattery {
                Text(L10n.t("battery.none"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if compact {
                compactBlock
            } else {
                detailBlock
            }
        }
    }

    private var compactBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(battery.batteryPercent)%")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 1) {
                    Text(battery.powerInLabel)
                        .font(.caption.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(TCTheme.sun)
                    Text(pinCurrentText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            powerCharts(compact: true)

            chargePills

            if battery.chargeMode == .custom {
                chargeRows(maxTint: TCTheme.grape)
            }
        }
    }

    private var detailBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(battery.batteryPercent)%")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(battery.powerInLabel)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(TCTheme.sun)
                    Text(detailPowerFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if battery.voltageMV > 0 {
                    Text(String(format: "%.1fV", battery.voltageMV / 1000))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TCTheme.lime.opacity(0.16), in: Capsule())
                }
            }

            ProgressView(value: Double(battery.batteryPercent), total: 100)
                .tint(battery.batteryPercent < 20 ? TCTheme.peach : TCTheme.lime)
                .scaleEffect(x: 1, y: 1.4, anchor: .center)

            powerCharts(compact: false)

            Text(battery.chargeStatusLabel)
                .font(.caption.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(battery.maintainActive ? TCTheme.grape : .secondary)

            chargePills

            if battery.chargeMode == .custom {
                chargeRows(maxTint: TCTheme.lime)
            }

            Toggle(L10n.t("battery.force"), isOn: Binding(
                get: { battery.forceDischarge },
                set: { battery.setForceDischarge($0) }
            ))
            .tint(TCTheme.peach)
            .disabled(!vm.controlsEnabled)
            Text(L10n.t("battery.force.hint"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var chargePills: some View {
        HStack(spacing: 8) {
            ChoicePill(title: L10n.t("battery.full"), symbol: "battery.100", selected: battery.chargeMode == .full, tint: TCTheme.lime, enabled: true) {
                battery.setChargeFull()
            }
            ChoicePill(title: L10n.t("mode.custom"), symbol: "percent", selected: battery.chargeMode == .custom, tint: TCTheme.grape, enabled: true) {
                battery.setChargeCustom()
            }
        }
    }

    private func chargeRows(maxTint: Color) -> some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            ConfigNumberRow(
                title: L10n.t("battery.min"),
                unit: "%",
                value: battery.chargeLowerBinding,
                tint: TCTheme.mint,
                enabled: true,
                onCommit: { battery.applyChargeLimit() },
                onLive: { battery.scheduleChargeApply() }
            )
            ConfigNumberRow(
                title: L10n.t("battery.max"),
                unit: "%",
                value: battery.chargePercentBinding,
                tint: maxTint,
                enabled: true,
                onCommit: { battery.applyChargeLimit() },
                onLive: { battery.scheduleChargeStop() }
            )
        }
    }

    private func powerCharts(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 8 : 12) {
            PowerSparkline(
                samples: power.powerHistory,
                maxWatts: power.powerChartMax,
                compact: compact,
                title: L10n.t("power.chart"),
                tint: TCTheme.sun
            )
            PowerSparkline(
                samples: power.usageHistory,
                maxWatts: power.usageChartMax,
                compact: compact,
                title: L10n.t("usage.chart"),
                tint: TCTheme.peach
            )
        }
    }

    private var pinCurrentText: String {
        let a = battery.amperageMA / 1000
        if abs(a) < 0.05 { return L10n.t("battery.current.zero") }
        if a > 0 { return L10n.t("battery.current.charge", a) }
        return L10n.t("battery.current.discharge", a)
    }

    private var detailPowerFootnote: String {
        var parts: [String] = []
        if battery.adapterWatts > 0 {
            parts.append(L10n.t("power.adapter", battery.adapterWatts))
        }
        if let name = battery.adapterName, !name.isEmpty {
            parts.append(name)
        }
        parts.append(pinCurrentText)
        return parts.joined(separator: " · ")
    }
}