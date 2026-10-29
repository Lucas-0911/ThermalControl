import SwiftUI

// ponytail: Section filter avoids duplicating fan UI code between MenuBar and multi-column Dashboard.
enum FanPanelSection {
    case all
    case visual
    case controls
}

struct FanPanel: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var fan: FanViewModel
    var compact: Bool
    var section: FanPanelSection = .all
    var allowsEditing = true

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            if compact {
                HStack(spacing: 6) {
                    Image(systemName: "fanblades.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TCTheme.fan)
                    Text(L10n.t("fan").uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(TCTheme.secondaryLabel)
                    Spacer()
                }
            }

            if !fan.showFan {
                HStack {
                    Image(systemName: "slash.circle")
                        .foregroundStyle(TCTheme.secondaryLabel)
                    Text(L10n.t("fan.none"))
                        .font(.caption)
                        .foregroundStyle(TCTheme.secondaryLabel)
                }
                .padding(.vertical, 4)
            } else {
                if section == .all || section == .visual {
                    gaugesView
                }

                if section == .all || section == .controls {
                    controlsView
                }
            }
        }
    }

    private var gaugesView: some View {
        HStack(spacing: compact ? 12 : 24) {
            ForEach(fan.fans, id: \.index) { f in
                FanGauge(
                    title: L10n.t("fan.n", f.index + 1),
                    rpm: fan.displayRPM(for: f),
                    minRPM: f.minRPM,
                    maxRPM: f.maxRPM,
                    glideGoal: fan.isRamping ? fan.goalRPM(for: f.index) : nil,
                    compact: compact
                )
                .id(f.index)
            }
        }
        .padding(.vertical, 2)
    }

    private var controlsEnabled: Bool {
        vm.controlsEnabled && fan.fanControl
    }

    private var controlsView: some View {
        VStack(spacing: 12) {
            if fan.isApplying {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(L10n.t("status.applying")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
            if fan.isRamping {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.t("fan.ramping"), systemImage: "arrow.up.arrow.down")
                    ForEach(fan.fans, id: \.index) { channel in
                        if let goal = fan.goalRPM(for: channel.index) {
                            Text(L10n.t("fan.ramp.progress", channel.index + 1,
                                        Int(channel.actualRPM.rounded()), Int(channel.targetRPM.rounded()),
                                        Int(goal.rounded())))
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            // Segmented Mode Switcher (Apple HIG Native Control style)
            HStack(spacing: 0) {
                ModeTile(
                    title: L10n.t("mode.auto"),
                    symbol: "sparkles",
                    selected: fan.desiredFanMode == .system,
                    tint: TCTheme.fan,
                    enabled: controlsEnabled,
                    compact: compact
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        fan.setFanMode(.system)
                    }
                }
                Divider().frame(height: 18)
                ModeTile(
                    title: L10n.t("mode.quiet"),
                    symbol: "moon.fill",
                    selected: fan.desiredFanMode == .quiet,
                    tint: TCTheme.quiet,
                    enabled: controlsEnabled,
                    compact: compact
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        fan.setFanMode(.quiet)
                    }
                }
                Divider().frame(height: 18)
                ModeTile(
                    title: L10n.t("mode.max"),
                    symbol: "bolt.fill",
                    selected: fan.desiredFanMode == .max,
                    tint: TCTheme.danger,
                    enabled: controlsEnabled,
                    compact: compact
                ) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        fan.setFanMode(.max)
                    }
                }
                Divider().frame(height: 18)
                ModeTile(
                    title: L10n.t("mode.custom"),
                    symbol: "slider.horizontal.3",
                    selected: fan.desiredFanMode == .manual || (allowsEditing && fan.editingFan),
                    tint: TCTheme.power,
                    enabled: controlsEnabled && !fan.isApplying,
                    compact: compact
                ) {
                    showCustomControl()
                }
            }
            .padding(2)
            .background(Color(nsColor: .controlColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(TCTheme.separator.opacity(0.35), lineWidth: 0.5)
            )

            Text(L10n.t("mode.quiet.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = fan.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(TCTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if allowsEditing && (fan.editingFan || fan.desiredFanMode == .manual) {
                VStack(spacing: 8) {
                    if let primary = fan.fans.min(by: { $0.index < $1.index }) {
                        ConfigNumberRow(
                            title: L10n.t("fan.n", primary.index + 1),
                            unit: "RPM",
                            value: fan.rpmFieldBinding(for: primary.index),
                            tint: TCTheme.power,
                            step: 100,
                            minVal: Int(fan.sliderMin(for: primary.index)),
                            maxVal: Int(fan.sliderMax(for: primary.index)),
                            enabled: controlsEnabled && fan.hasValidFanLimits && !fan.isApplying
                        )
                        ForEach(fan.fans.filter { $0.index != primary.index }, id: \.index) { other in
                            Text("\(L10n.t("fan.n", other.index + 1)) · \(fan.balancedRPM(for: other.index)) RPM")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    HStack {
                        Text(L10n.t("edit.draft"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.t("cancel"), action: fan.cancelFanEdits)
                            .disabled(fan.isApplying)
                        Button(L10n.t("apply"), action: fan.setManualRPM)
                            .buttonStyle(.borderedProminent)
                            .disabled(!controlsEnabled || !fan.hasValidFanLimits || fan.isApplying)
                    }
                }
            }
        }
    }

    private func showCustomControl() {
        if allowsEditing {
            fan.selectFanCustom()
        } else {
            fan.applySavedCustom()
        }
    }
}
