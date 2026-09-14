import SwiftUI

struct BatteryPanel: View {
    @EnvironmentObject var vm: ThermalViewModel
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if compact {
                Label(L10n.t("battery"), systemImage: "battery.100.bolt")
                    .font(.headline.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(TCTheme.lime)
            }
            if !vm.showBattery {
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
                Text("\(vm.batteryPercent)%")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 1) {
                    Text(vm.powerInLabel)
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

            HStack(spacing: 8) {
                ChoicePill(title: L10n.t("battery.full"), symbol: "battery.100", selected: vm.chargeMode == .full, tint: TCTheme.lime, enabled: true) {
                    vm.setChargeFull()
                }
                ChoicePill(title: L10n.t("mode.custom"), symbol: "percent", selected: vm.chargeMode == .custom, tint: TCTheme.grape, enabled: true) {
                    vm.setChargeCustom()
                }
            }

            if vm.chargeMode == .custom {
                ConfigNumberRow(
                    title: L10n.t("battery.min"),
                    unit: "%",
                    value: vm.chargeLowerBinding,
                    tint: TCTheme.mint,
                    enabled: true,
                    onCommit: { vm.applyChargeLimit() },
                    onLive: { vm.scheduleChargeApply() }
                )
                ConfigNumberRow(
                    title: L10n.t("battery.max"),
                    unit: "%",
                    value: vm.chargePercentBinding,
                    tint: TCTheme.grape,
                    enabled: true,
                    onCommit: { vm.applyChargeLimit() },
                    onLive: { vm.scheduleChargeStop() }
                )
            }
        }
    }

    private var detailBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(vm.batteryPercent)%")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.powerInLabel)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(TCTheme.sun)
                    Text(detailPowerFootnote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if vm.voltageMV > 0 {
                    Text(String(format: "%.1fV", vm.voltageMV / 1000))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TCTheme.lime.opacity(0.16), in: Capsule())
                }
            }

            ProgressView(value: Double(vm.batteryPercent), total: 100)
                .tint(vm.batteryPercent < 20 ? TCTheme.peach : TCTheme.lime)
                .scaleEffect(x: 1, y: 1.4, anchor: .center)

            powerCharts(compact: false)

            Text(vm.chargeStatusLabel)
                .font(.caption.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(vm.maintainActive ? TCTheme.grape : .secondary)

            HStack(spacing: 8) {
                ChoicePill(title: L10n.t("battery.full"), symbol: "battery.100", selected: vm.chargeMode == .full, tint: TCTheme.lime, enabled: true) {
                    vm.setChargeFull()
                }
                ChoicePill(title: L10n.t("mode.custom"), symbol: "percent", selected: vm.chargeMode == .custom, tint: TCTheme.grape, enabled: true) {
                    vm.setChargeCustom()
                }
            }

            if vm.chargeMode == .custom {
                ConfigNumberRow(
                    title: L10n.t("battery.min"),
                    unit: "%",
                    value: vm.chargeLowerBinding,
                    tint: TCTheme.mint,
                    enabled: true,
                    onCommit: { vm.applyChargeLimit() },
                    onLive: { vm.scheduleChargeApply() }
                )
                ConfigNumberRow(
                    title: L10n.t("battery.max"),
                    unit: "%",
                    value: vm.chargePercentBinding,
                    tint: TCTheme.lime,
                    enabled: true,
                    onCommit: { vm.applyChargeLimit() },
                    onLive: { vm.scheduleChargeStop() }
                )
            }

            Toggle(L10n.t("battery.force"), isOn: Binding(
                get: { vm.forceDischarge },
                set: { vm.setForceDischarge($0) }
            ))
            .tint(TCTheme.peach)
            .disabled(!vm.controlsEnabled)
            Text(L10n.t("battery.force.hint"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func powerCharts(compact: Bool) -> some View {
        HStack(alignment: .top, spacing: compact ? 8 : 12) {
            PowerSparkline(
                samples: vm.powerHistory,
                maxWatts: vm.powerChartMax,
                compact: compact,
                title: L10n.t("power.chart"),
                tint: TCTheme.sun
            )
            PowerSparkline(
                samples: vm.usageHistory,
                maxWatts: vm.usageChartMax,
                compact: compact,
                title: L10n.t("usage.chart"),
                tint: TCTheme.peach
            )
        }
    }

    private var pinCurrentText: String {
        let a = vm.amperageMA / 1000
        if abs(a) < 0.05 { return L10n.t("battery.current.zero") }
        if a > 0 { return L10n.t("battery.current.charge", a) }
        return L10n.t("battery.current.discharge", a)
    }

    private var detailPowerFootnote: String {
        var parts: [String] = []
        if vm.adapterWatts > 0 {
            parts.append(L10n.t("power.adapter", vm.adapterWatts))
        }
        if let name = vm.adapterName, !name.isEmpty {
            parts.append(name)
        }
        parts.append(pinCurrentText)
        return parts.joined(separator: " · ")
    }
}
