import SwiftUI

// ponytail: Section filter avoids duplicating battery UI code between MenuBar and multi-column Dashboard.
enum BatteryPanelSection {
    case all
    case visual
    case controls
}

struct BatteryPanel: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var battery: BatteryViewModel
    @EnvironmentObject var power: PowerViewModel
    var compact: Bool
    var section: BatteryPanelSection = .all
    var allowsEditing = true
    @State private var confirmingDischarge = false

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
                if section == .all || section == .visual {
                    visualContent
                }

                if section == .all || section == .controls {
                    controlsContent
                }
            }
        }
    }

    private var visualContent: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            percentHeader

            // Continuous Battery Capacity Bar
            batteryCapacityBar

            if battery.powerUnavailable {
                Label(L10n.t("status.stale"), systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                powerCharts
            }

            if !compact {
                Text(battery.chargeStatusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(battery.maintainActive ? TCTheme.charge : TCTheme.secondaryLabel)
            }
        }
    }

    private var controlsEnabled: Bool {
        vm.controlsEnabled && battery.batteryControl && battery.canControlCharge
            && battery.hasConfirmedChargeState && !battery.applyingCharge
    }

    private var controlsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !battery.hasConfirmedChargeState {
                Label(L10n.t("error.readback"), systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if battery.applyingCharge {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("status.applying")).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            chargeModeRow
            if compact && !allowsEditing && battery.chargeMode == .custom {
                menuPresetRow
            }

            if let error = battery.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(TCTheme.danger)
            }

            if allowsEditing {
                if battery.editingCharge {
                    chargeRows
                } else {
                    Button(L10n.t("battery.edit"), action: battery.beginChargeEdits)
                        .disabled(!controlsEnabled)
                }
            }
            if battery.needsDischargeStop {
                if battery.forceDischarge {
                    Text(L10n.t("battery.force.progress", battery.dischargeTargetPercent,
                                Int(ceil(battery.dischargeRemainingSeconds / 60))))
                        .font(.caption)
                }
                if battery.isDischargeStopPending {
                    Label(L10n.t("battery.force.stop.pending"), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(TCTheme.danger)
                }
                Button(L10n.t("battery.force.stop")) { battery.setForceDischarge(false) }
                    .buttonStyle(.borderedProminent)
            }
            if allowsEditing && battery.forceDischargeControl {
                forceDischargeSection
            }
        }
    }

    private var menuPresetRow: some View {
        presetChrome {
            menuPreset(60)
            Divider().frame(height: 16)
            menuPreset(80)
            Divider().frame(height: 16)
            menuPreset(90)
        }
    }

    private func menuPreset(_ upper: Int) -> some View {
        ChoicePill(
            title: "\(upper)%",
            symbol: "shield.lefthalf.filled",
            selected: battery.menuPresetIsSelected(upper: upper),
            tint: TCTheme.charge,
            enabled: controlsEnabled
        ) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                battery.applyMenuPreset(upper: upper)
            }
        }
    }

    private var chargeModeRow: some View {
        presetChrome {
            ChoicePill(
                title: L10n.t("battery.full"),
                symbol: "battery.100",
                selected: battery.chargeMode == .full,
                tint: TCTheme.battery,
                enabled: controlsEnabled
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
                enabled: controlsEnabled
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if compact && !allowsEditing {
                        battery.selectMenuLimit()
                    } else {
                        battery.setChargeCustom()
                    }
                }
            }
        }
    }

    private func presetChrome<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0, content: content)
            .padding(2)
            .background(Color(nsColor: .controlColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(TCTheme.separator.opacity(0.35), lineWidth: 0.5)
            )
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
                        Text(L10n.t("power.adapter", battery.adapterWatts))
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
                minVal: ChargeLimits.minUpper,
                maxVal: ChargeLimits.maxPercent,
                enabled: controlsEnabled
            )

            ConfigNumberRow(
                title: L10n.t("battery.resume"),
                unit: "%",
                value: battery.chargeLowerBinding,
                tint: TCTheme.charge,
                step: 5,
                minVal: ChargeLimits.minPercent,
                maxVal: battery.savedChargeUpper - ChargeLimits.minGap,
                enabled: controlsEnabled
            )

            Text(L10n.t("charge.range", battery.savedChargeUpper, battery.draftChargeLower))
                .font(.system(size: 11))
                .foregroundStyle(TCTheme.secondaryLabel)
                .padding(.horizontal, 4)
            HStack {
                Text(L10n.t("edit.draft"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.t("cancel"), action: battery.cancelChargeEdits)
                    .disabled(battery.applyingCharge)
                Button(L10n.t("apply"), action: battery.applyChargeLimit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!controlsEnabled)
            }
        }
    }

    // ponytail: Always show both Power and Usage sparklines side-by-side so power in vs power drain are both visible.
    private var powerCharts: some View {
        HStack(spacing: compact ? 8 : DS.Space.m) {
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

    private var forceDischargeSection: some View {
        DisclosureGroup(L10n.t("battery.advanced")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("battery.force.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if battery.dischargeStopVerified && battery.dischargeStopReason != nil && !battery.forceDischarge {
                    Text(battery.dischargeStopLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !battery.needsDischargeStop {
                    Button(L10n.t("battery.force.start")) { confirmingDischarge = true }
                        .disabled(!battery.canStartDischarge)
                    if !battery.canStartDischarge {
                        Text(L10n.t("battery.force.precondition"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 8)
        }
        .alert(L10n.t("battery.force.confirm.title"), isPresented: $confirmingDischarge) {
            Button(L10n.t("cancel"), role: .cancel) {}
            Button(L10n.t("battery.force.start"), role: .destructive) { battery.setForceDischarge(true) }
        } message: {
            Text(L10n.t("battery.force.confirm.body", battery.chargeUpper))
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
