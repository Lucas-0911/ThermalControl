import SwiftUI

struct FanPanel: View {
    @EnvironmentObject var fan: FanViewModel
    var compact: Bool

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
                // Fan Radial Gauges
                HStack(spacing: compact ? 12 : 24) {
                    ForEach(fan.fans, id: \.index) { f in
                        FanGauge(
                            title: L10n.t("fan.n", f.index + 1),
                            rpm: fan.displayRPM(for: f),
                            minRPM: f.minRPM,
                            maxRPM: f.maxRPM,
                            compact: compact
                        )
                        .id(f.index)
                    }
                }
                .padding(.vertical, 2)

                // Segmented Mode Switcher (Apple HIG Native Control style)
                HStack(spacing: 0) {
                    ModeTile(
                        title: L10n.t("mode.auto"),
                        symbol: "sparkles",
                        selected: fan.desiredFanMode == .system,
                        tint: TCTheme.fan,
                        enabled: true,
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
                        enabled: true,
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
                        enabled: true,
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
                        selected: fan.desiredFanMode == .manual,
                        tint: TCTheme.power,
                        enabled: true,
                        compact: compact
                    ) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            fan.selectFanCustom()
                        }
                    }
                }
                .padding(2)
                .background(Color(nsColor: .controlColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(TCTheme.separator.opacity(0.35), lineWidth: 0.5)
                )

                // Custom RPM Slider & Precise Stepper
                if fan.desiredFanMode == .manual {
                    VStack(spacing: 8) {
                        if compact {
                            // Quick RPM Slider
                            Slider(
                                value: Binding(
                                    get: { Double(fan.manualRPM) },
                                    set: {
                                        fan.manualRPM = Int($0)
                                        fan.scheduleFanApply(index: -1)
                                    }
                                ),
                                in: fan.sliderMin...fan.sliderMax,
                                step: 50
                            )
                            .tint(TCTheme.power)

                            ConfigNumberRow(
                                title: L10n.t("mode.custom"),
                                unit: "RPM",
                                value: fan.rpmFieldBinding,
                                tint: TCTheme.power,
                                step: 100,
                                minVal: Int(fan.sliderMin),
                                maxVal: Int(fan.sliderMax),
                                enabled: true,
                                onCommit: { fan.setManualRPM() },
                                onLive: { fan.scheduleFanApply(index: -1) }
                            )
                        } else {
                            ForEach(fan.fans, id: \.index) { f in
                                VStack(alignment: .leading, spacing: 6) {
                                    Slider(
                                        value: Binding(
                                            get: { Double(fan.draftRPM(for: f.index)) },
                                            set: {
                                                fan.fanDrafts[f.index] = Int($0)
                                                fan.scheduleFanApply(index: f.index)
                                            }
                                        ),
                                        in: fan.sliderMin(for: f.index)...fan.sliderMax(for: f.index),
                                        step: 50
                                    )
                                    .tint(TCTheme.power)

                                    ConfigNumberRow(
                                        title: L10n.t("fan.n", f.index + 1),
                                        unit: "RPM",
                                        value: fan.rpmFieldBinding(for: f.index),
                                        tint: TCTheme.power,
                                        step: 100,
                                        minVal: Int(fan.sliderMin(for: f.index)),
                                        maxVal: Int(fan.sliderMax(for: f.index)),
                                        enabled: true,
                                        onCommit: { fan.setFanRPM(fan.savedRPM(for: f.index), index: f.index) },
                                        onLive: { fan.scheduleFanApply(index: f.index) }
                                    )
                                }
                            }
                        }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }
}
