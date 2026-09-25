import SwiftUI

/// Battery + charge-limit panel. Phase 5: compact/detail merged into one
/// layout with conditional sections (previously two near-duplicate blocks
/// with copy-pasted charge rows), restyled to the native palette.
struct BatteryPanel: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var battery: BatteryViewModel
    @EnvironmentObject var power: PowerViewModel
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? DS.Space.s + 2 : DS.Space.m) {
            if compact {
                Label(L10n.t("battery"), systemImage: "battery.100.bolt")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TCTheme.secondaryLabel)
            }
            if !battery.showBattery {
                Text(L10n.t("battery.none"))
                    .font(.caption)
                    .foregroundStyle(TCTheme.secondaryLabel)
            } else {
                percentHeader
                if !compact {
                    ProgressView(value: Double(battery.batteryPercent), total: 100)
                        .tint(battery.batteryPercent < 20 ? TCTheme.danger : TCTheme.battery)
                }
                powerCharts
                if !compact {
                    Text(battery.chargeStatusLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(battery.maintainActive ? TCTheme.quiet : TCTheme.secondaryLabel)
                }
                chargePills
                if battery.chargeMode == .custom {
                    chargeRows
                }
                if !compact {
                    forceDischargeSection
                }
            }
        }
    }

    private var percentHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s + 2) {
            Text("\(battery.batteryPercent)%")
                .font(.system(size: compact ? DS.Typography.metric + 4 : DS.Typography.metricLarge, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TCTheme.label)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(battery.powerInLabel)
                    .font(compact ? .caption.weight(.semibold) : .callout.weight(.semibold))
                    .foregroundStyle(TCTheme.power)
                Text(compact ? pinCurrentText : detailPowerFootnote)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(TCTheme.secondaryLabel)
            }
            Spacer()
            if !compact, battery.voltageMV > 0 {
                Text(String(format: "%.1fV", battery.voltageMV / 1000))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(TCTheme.secondaryLabel)
            }
        }
    }

    private var chargePills: some View {
        HStack(spacing: DS.Space.s) {
            ChoicePill(title: L10n.t("battery.full"), symbol: "battery.100", selected: battery.chargeMode == .full, tint: TCTheme.battery, enabled: true) {
                battery.setChargeFull()
            }
            ChoicePill(title: L10n.t("mode.custom"), symbol: "percent", selected: battery.chargeMode == .custom, tint: TCTheme.quiet, enabled: true) {
                battery.setChargeCustom()
            }
        }
    }

    private var chargeRows: some View {
        VStack(alignment: .leading, spacing: compact ? DS.Space.s + 2 : DS.Space.m) {
            ConfigNumberRow(
                title: L10n.t("battery.min"),
                unit: "%",
                value: battery.chargeLowerBinding,
                tint: TCTheme.charge,
                enabled: true,
                onCommit: { battery.applyChargeLimit() },
                onLive: { battery.scheduleChargeApply() }
            )
            ConfigNumberRow(
                title: L10n.t("battery.max"),
                unit: "%",
                value: battery.chargePercentBinding,
                tint: TCTheme.quiet,
                enabled: true,
                onCommit: { battery.applyChargeLimit() },
                onLive: { battery.scheduleChargeStop() }
            )
        }
    }

    private var forceDischargeSection: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Toggle(L10n.t("battery.force"), isOn: Binding(
                get: { battery.forceDischarge },
                set: { battery.setForceDischarge($0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(TCTheme.danger)
            .disabled(!vm.controlsEnabled)
            Text(L10n.t("battery.force.hint"))
                .font(.caption2)
                .foregroundStyle(TCTheme.tertiaryLabel)
        }
    }

    private var powerCharts: some View {
        HStack(alignment: .top, spacing: compact ? DS.Space.s : DS.Space.m) {
            PowerSparkline(
                samples: power.powerHistory,
                maxWatts: power.powerChartMax,
                compact: compact,
                title: L10n.t("power.chart"),
                tint: TCTheme.power
            )
            PowerSparkline(
                samples: power.usageHistory,
                maxWatts: power.usageChartMax,
                compact: compact,
                title: L10n.t("usage.chart"),
                tint: TCTheme.temperature
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