import SwiftUI

struct BatteryPanel: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var battery: BatteryViewModel
    @EnvironmentObject var power: PowerViewModel
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            if compact {
                HStack(spacing: 6) {
                    Image(systemName: "battery.100.bolt")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TCTheme.battery)
                    Text(L10n.t("battery").uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(TCTheme.secondaryLabel)
                    Spacer()
                }
            }

            if !battery.showBattery {
                HStack {
                    Image(systemName: "slash.circle")
                        .foregroundStyle(TCTheme.secondaryLabel)
                    Text(L10n.t("battery.none"))
                        .font(.caption)
                        .foregroundStyle(TCTheme.secondaryLabel)
                }
                .padding(.vertical, 4)
            } else {
                percentHeader

                // Continuous Battery Capacity Bar
                batteryCapacityBar

                powerCharts

                if !compact {
                    Text(battery.chargeStatusLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(battery.maintainActive ? TCTheme.charge : TCTheme.secondaryLabel)
                }

                // Native Segmented Control for Charge Mode
                HStack(spacing: 0) {
                    ChoicePill(
                        title: L10n.t("battery.full"),
                        symbol: "battery.100",
                        selected: battery.chargeMode == .full,
                        tint: TCTheme.battery,
                        enabled: true
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            battery.setChargeFull()
                        }
                    }
                    Divider().frame(height: 16)
                    ChoicePill(
                        title: L10n.t("battery.limit"),
                        symbol: "shield.lefthalf.filled",
                        selected: battery.chargeMode == .custom,
                        tint: TCTheme.charge,
                        enabled: true
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            battery.setChargeCustom()
                        }
                    }
                }
                .padding(2)
                .background(Color(nsColor: .controlColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(TCTheme.separator.opacity(0.35), lineWidth: 0.5)
                )

                if battery.chargeMode == .custom {
                    chargeRows
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !compact {
                    forceDischargeSection
                }
            }
        }
    }

    private var percentHeader: some View {
        HStack(alignment: .center, spacing: DS.Space.s + 2) {
            // Big percentage number
            Text("\(battery.batteryPercent)%")
                .font(.system(size: compact ? 26 : 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(TCTheme.label)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: battery.externalAC ? "powerplug.fill" : "battery.50")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(battery.maintainActive ? TCTheme.charge : TCTheme.power)
                    Text(battery.powerInLabel)
                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
                        .foregroundStyle(battery.maintainActive ? TCTheme.charge : TCTheme.power)
                }

                Text(compact ? pinCurrentText : detailPowerFootnote)
                    .font(.system(size: 11))
                    .foregroundStyle(TCTheme.secondaryLabel)
            }

            Spacer()

            if !compact, battery.voltageMV > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f V", battery.voltageMV / 1000))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(TCTheme.secondaryLabel)
                    if battery.adapterWatts > 0 {
                        Text(String(format: "%.0fW In", battery.adapterWatts))
                            .font(.system(size: 11))
                            .foregroundStyle(TCTheme.tertiaryLabel)
                    }
                }
            }
        }
    }

    private var batteryCapacityBar: some View {
        GeometryReader { geo in
            let pct = min(max(Double(battery.batteryPercent) / 100.0, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.2))

                Capsule()
                    .fill(
                        battery.maintainActive
                            ? AnyShapeStyle(TCTheme.charge)
                            : (battery.batteryPercent <= 20
                               ? AnyShapeStyle(TCTheme.danger)
                               : AnyShapeStyle(TCTheme.battery))
                    )
                    .frame(width: max(6, geo.size.width * pct))
            }
        }
        .frame(height: 6)
    }

    private var chargeRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConfigNumberRow(
                title: L10n.t("battery.stop"),
                unit: "%",
                value: battery.chargePercentBinding,
                tint: TCTheme.charge,
                step: 5,
                minVal: 50,
                maxVal: 95,
                enabled: true,
                onCommit: { battery.applyChargeLimit() },
                onLive: { battery.scheduleChargeStop() }
            )

            ConfigNumberRow(
                title: L10n.t("battery.resume"),
                unit: "%",
                value: battery.chargeLowerBinding,
                tint: TCTheme.charge,
                step: 5,
                minVal: 40,
                maxVal: battery.chargeUpper - 1,
                enabled: true,
                onCommit: { battery.applyChargeLimit() },
                onLive: { battery.scheduleChargeApply() }
            )

            Text(L10n.t("charge.range", battery.chargeUpper, battery.chargeLower))
                .font(.system(size: 11))
                .foregroundStyle(TCTheme.secondaryLabel)
                .padding(.horizontal, 4)
        }
    }

    private var powerCharts: some View {
        Group {
            if compact {
                if battery.externalAC {
                    PowerSparkline(
                        samples: power.powerHistory,
                        maxWatts: power.powerChartMax,
                        compact: true,
                        title: L10n.t("power.chart"),
                        tint: TCTheme.power
                    )
                } else {
                    PowerSparkline(
                        samples: power.usageHistory,
                        maxWatts: power.usageChartMax,
                        compact: true,
                        title: L10n.t("usage.chart"),
                        tint: TCTheme.fan
                    )
                }
            } else {
                HStack(spacing: DS.Space.m) {
                    if battery.externalAC {
                        PowerSparkline(
                            samples: power.powerHistory,
                            maxWatts: power.powerChartMax,
                            compact: false,
                            title: L10n.t("power.chart"),
                            tint: TCTheme.power
                        )
                    }
                    PowerSparkline(
                        samples: power.usageHistory,
                        maxWatts: power.usageChartMax,
                        compact: false,
                        title: L10n.t("usage.chart"),
                        tint: TCTheme.fan
                    )
                }
            }
        }
    }

    private var forceDischargeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { battery.forceDischarge },
                set: { battery.setForceDischarge($0) }
            )) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(TCTheme.danger)
                    Text(L10n.t("battery.force"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TCTheme.label)
                }
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            Text(L10n.t("battery.force.hint"))
                .font(.caption2)
                .foregroundStyle(TCTheme.secondaryLabel)
                .padding(.leading, 18)
        }
        .padding(.top, 4)
    }

    private var pinCurrentText: String {
        let a = battery.amperageMA / 1000.0
        if abs(a) < 0.05 { return L10n.t("battery.current.zero") }
        if a > 0 { return L10n.t("battery.current.charge", a) }
        return L10n.t("battery.current.discharge", abs(a))
    }

    private var detailPowerFootnote: String {
        var parts: [String] = []
        if battery.externalAC {
            if let n = battery.adapterName, !n.isEmpty { parts.append(n) }
            if battery.adapterWatts > 0 {
                parts.append(String(format: "%.0fW", battery.adapterWatts))
            }
        } else {
            parts.append(L10n.t("power.on.battery"))
        }
        parts.append(pinCurrentText)
        return parts.joined(separator: " · ")
    }
}
