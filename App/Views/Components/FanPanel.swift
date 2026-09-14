import SwiftUI

struct FanPanel: View {
    @EnvironmentObject var vm: ThermalViewModel
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if compact {
                Label(L10n.t("fan"), systemImage: "fanblades.fill")
                    .font(.headline.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(TCTheme.cyan)
            }
            if !vm.showFan {
                Text(L10n.t("fan.none"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: compact ? 8 : 16) {
                    ForEach(vm.fans, id: \.index) { f in
                        FanGauge(
                            title: L10n.t("fan.n", f.index + 1),
                            rpm: vm.displayRPM(for: f),
                            minRPM: f.minRPM,
                            maxRPM: f.maxRPM,
                            compact: compact
                        )
                        .id(f.index)
                    }
                }

                HStack(spacing: 8) {
                    ModeTile(title: L10n.t("mode.auto"), symbol: "switch.2", selected: vm.desiredFanMode == .system, tint: TCTheme.grape, enabled: true, compact: compact) {
                        vm.setFanMode(.system)
                    }
                    ModeTile(title: L10n.t("mode.quiet"), symbol: "moon.stars.fill", selected: vm.desiredFanMode == .quiet, tint: TCTheme.cyan, enabled: true, compact: compact) {
                        vm.setFanMode(.quiet)
                    }
                    ModeTile(title: L10n.t("mode.max"), symbol: "bolt.fill", selected: vm.desiredFanMode == .max, tint: TCTheme.peach, enabled: true, compact: compact) {
                        vm.setFanMode(.max)
                    }
                    ModeTile(title: L10n.t("mode.custom"), symbol: "keyboard", selected: vm.desiredFanMode == .manual, tint: TCTheme.sun, enabled: true, compact: compact) {
                        vm.selectFanCustom()
                    }
                }

                if vm.desiredFanMode == .manual {
                    if compact {
                        ConfigNumberRow(
                            title: L10n.t("mode.custom"),
                            unit: "RPM",
                            value: vm.rpmFieldBinding,
                            tint: TCTheme.sun,
                            enabled: true,
                            onCommit: { vm.setManualRPM() },
                            onLive: { vm.scheduleFanApply(index: -1) }
                        )
                    } else {
                        ForEach(vm.fans, id: \.index) { f in
                            ConfigNumberRow(
                                title: L10n.t("fan.n", f.index + 1),
                                unit: "RPM",
                                value: vm.rpmFieldBinding(for: f.index),
                                tint: TCTheme.sun,
                                enabled: true,
                                onCommit: { vm.setFanRPM(vm.savedRPM(for: f.index), index: f.index) },
                                onLive: { vm.scheduleFanApply(index: f.index) }
                            )
                        }
                    }
                }
            }
        }
    }
}
