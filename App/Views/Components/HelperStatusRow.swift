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
            VStack(alignment: .leading, spacing: DS.Space.s) {
                if detailed {
                    LabeledContent(L10n.t("helper"), value: vm.helperStatusText)
                    LabeledContent("SMAppService", value: vm.smAppServiceState)
                    LabeledContent(L10n.t("helper.fan"), value: fan.fanControl ? L10n.t("yes") : L10n.t("no"))
                    LabeledContent(L10n.t("helper.battery"), value: battery.batteryControl ? L10n.t("yes") : L10n.t("no"))
                } else {
                    Text(vm.helperStatusText)
                        .font(.caption)
                        .foregroundStyle(TCTheme.secondaryLabel)
                }
                if vm.connectionState != .connected {
                    HStack(spacing: DS.Space.s) {
                        Button(L10n.t("perm.allow")) { vm.showHelperPermissionAlert(force: true) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(vm.connectionState == .connecting)
                        Button(L10n.t("helper.loginItems")) { vm.openLoginItems() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button(L10n.t("helper.reconnect")) { vm.reconnect() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                } else if detailed {
                    Button(L10n.t("helper.reconnect")) { vm.reconnect() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }
}