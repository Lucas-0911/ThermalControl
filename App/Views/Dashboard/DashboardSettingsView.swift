import SwiftUI

struct DashboardSettingsView: View {
    @EnvironmentObject private var vm: ThermalViewModel
    @EnvironmentObject private var lang: LanguageSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            metrics
            HStack(alignment: .top, spacing: 20) {
                PanelCard(title: L10n.t("settings"), symbol: "gearshape.fill", tint: TCTheme.accent) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(L10n.t("language"))
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Picker("", selection: $lang.selection) {
                                Text(L10n.t("language.system")).tag("system")
                                Text("English").tag("en")
                                Text("Tiếng Việt").tag("vi")
                            }
                            .pickerStyle(.menu)
                            .frame(width: 140)
                            .accessibilityLabel(L10n.t("language"))
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.t("login.start"))
                                    .font(.system(size: 13, weight: .medium))
                                Text(L10n.t("login.start.hint"))
                                    .font(.caption)
                                    .foregroundStyle(TCTheme.secondaryLabel)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { vm.startAtLogin },
                                set: vm.setStartAtLogin
                            ))
                            .toggleStyle(.switch)
                            .accessibilityLabel(L10n.t("login.start"))
                        }
                    }
                }
                PanelCard(title: L10n.t("helper"), symbol: "shield.lefthalf.filled", tint: TCTheme.quiet) {
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        HelperStatusRow(detailed: true)
                        Divider()
                        Text(L10n.t("helper.hint"))
                            .font(.caption)
                            .foregroundStyle(TCTheme.secondaryLabel)
                    }
                }
            }
        }
    }

    private var metrics: some View {
        HStack(spacing: DS.Space.m) {
            MetricTile(
                title: L10n.t("helper"),
                value: vm.connectionState == .connected ? L10n.t("status.connected") : L10n.t("offline"),
                symbol: "shield.lefthalf.filled",
                tint: vm.connectionState == .connected ? TCTheme.battery : TCTheme.danger,
                footnote: HelperStatusRow.serviceLabel(vm.smAppServiceState)
            )
            MetricTile(
                title: L10n.t("language"),
                value: languageName,
                symbol: "globe",
                tint: TCTheme.accent,
                footnote: lang.code == "vi" ? "Tiếng Việt" : "English"
            )
            MetricTile(
                title: L10n.t("login.start"),
                value: vm.startAtLogin ? L10n.t("enabled") : L10n.t("disabled"),
                symbol: "arrow.clockwise.circle",
                tint: TCTheme.quiet,
                footnote: L10n.t("login.launch.boot")
            )
            MetricTile(
                title: L10n.t("app.version"),
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                symbol: "info.circle",
                tint: TCTheme.secondaryLabel,
                footnote: L10n.t("app.universal")
            )
        }
    }

    private var languageName: String {
        switch lang.selection {
        case "vi": return "Tiếng Việt"
        case "en": return "English"
        default: return L10n.t("language.system")
        }
    }
}
