import SwiftUI

struct FanPanel: View {
    @EnvironmentObject var fan: FanViewModel
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if compact {
                Label(L10n.t("fan"), systemImage: "fanblades.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TCTheme.secondaryLabel)
            }
            if !fan.showFan {
                Text(L10n.t("fan.none"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: compact ? 8 : 16) {
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

                HStack(spacing: 8) {
                    ModeTile(title: L10n.t("mode.auto"), symbol: "switch.2", selected: fan.desiredFanMode == .system, tint: TCTheme.accent, enabled: true, compact: compact) {
                        fan.setFanMode(.system)
                    }
                    ModeTile(title: L10n.t("mode.quiet"), symbol: "moon.stars.fill", selected: fan.desiredFanMode == .quiet, tint: TCTheme.quiet, enabled: true, compact: compact) {
                        fan.setFanMode(.quiet)
                    }
                    ModeTile(title: L10n.t("mode.max"), symbol: "bolt.fill", selected: fan.desiredFanMode == .max, tint: TCTheme.danger, enabled: true, compact: compact) {
                        fan.setFanMode(.max)
                    }
                    ModeTile(title: L10n.t("mode.custom"), symbol: "keyboard", selected: fan.desiredFanMode == .manual, tint: TCTheme.power, enabled: true, compact: compact) {
                        fan.selectFanCustom()
                    }
                }

                if fan.desiredFanMode == .manual {
                    if compact {
                        ConfigNumberRow(
                            title: L10n.t("mode.custom"),
                            unit: "RPM",
                            value: fan.rpmFieldBinding,
                            tint: TCTheme.power,
                            enabled: true,
                            onCommit: { fan.setManualRPM() },
                            onLive: { fan.scheduleFanApply(index: -1) }
                        )
                    } else {
                        ForEach(fan.fans, id: \.index) { f in
                            ConfigNumberRow(
                                title: L10n.t("fan.n", f.index + 1),
                                unit: "RPM",
                                value: fan.rpmFieldBinding(for: f.index),
                                tint: TCTheme.power,
                                enabled: true,
                                onCommit: { fan.setFanRPM(fan.savedRPM(for: f.index), index: f.index) },
                                onLive: { fan.scheduleFanApply(index: f.index) }
                            )
                        }
                    }
                }
            }
        }
    }
}