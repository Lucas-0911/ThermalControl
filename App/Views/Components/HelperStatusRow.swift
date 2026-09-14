import SwiftUI

struct HelperStatusRow: View {
    @EnvironmentObject var vm: ThermalViewModel
    @EnvironmentObject var fan: FanViewModel
    @EnvironmentObject var battery: BatteryViewModel
    var detailed = false

    var body: some View {
        if vm.connectionState == .connected && !detailed {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if detailed {
                    LabeledContent(L10n.t("helper"), value: vm.helperStatusText)
                    LabeledContent("SMAppService", value: vm.smAppServiceState)
                    LabeledContent(L10n.t("helper.fan"), value: fan.fanControl ? L10n.t("yes") : L10n.t("no"))
                    LabeledContent(L10n.t("helper.battery"), value: battery.batteryControl ? L10n.t("yes") : L10n.t("no"))
                } else {
                    Text(vm.helperStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if vm.connectionState != .connected {
                    HStack(spacing: 8) {
                        Button(L10n.t("perm.allow")) { vm.showHelperPermissionAlert(force: true) }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(.white)
                            .background(TCTheme.grape, in: Capsule())
                            .disabled(vm.connectionState == .connecting)
                        Button(L10n.t("helper.loginItems")) { vm.openLoginItems() }
                            .font(.caption.weight(.semibold))
                        Button(L10n.t("helper.reconnect")) { vm.reconnect() }
                            .font(.caption.weight(.semibold))
                    }
                } else if detailed {
                    Button(L10n.t("helper.reconnect")) { vm.reconnect() }
                        .controlSize(.small)
                }
            }
        }
    }
}
