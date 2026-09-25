import SwiftUI

struct TempPanel: View {
    @EnvironmentObject var vm: ThermalViewModel
    var compact: Bool = true

    /// Hardware-sensor names without localization keys (core labels).
    /// The localized entries (TC0P/Tg0P/Ts0P/Ts0G) resolve through `L10n`
    /// in `label(for:)` at render time — previously a static dict captured
    /// translations at type-init, which only refreshed thanks to the
    /// `.id(lang.selection)` view-tree rebuild.
    private static let coreNames: [String: String] = [
        "Tp01": "CPU P1",
        "Tp05": "CPU P2",
        "Tp09": "CPU E",
        "Tp0D": "CPU P3",
        "Tp0H": "CPU P4",
        "Tp0L": "CPU E2",
        "Tp0T": "CPU E3",
        "Tp0b": "CPU P5",
        "Tp0f": "CPU P6",
        "Tg05": "GPU 1",
        "Tg0D": "GPU 2",
        "Tg0L": "GPU 3",
        "Tg0T": "GPU 4",
        "Tg0b": "GPU die",
        "Tg0f": "GPU die 2",
        "Tg1F": "GPU",
        "Te05": "GPU",
        "Te0F": "GPU",
        "Te0P": "GPU",
    ]

    private func label(for key: String) -> String {
        switch key {
        case SMCKey.tc0P.rawValue: return L10n.t("temp.cpu.prox")
        case SMCKey.tg0P.rawValue: return L10n.t("temp.gpu.prox")
        case SMCKey.ts0P.rawValue: return L10n.t("temp.skin")
        case SMCKey.ts0G.rawValue: return L10n.t("temp.gpu.skin")
        default: return Self.coreNames[key] ?? key
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s + 2) {
            if compact {
                Label(L10n.t("temp"), systemImage: "thermometer.medium")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TCTheme.secondaryLabel)
            }
            if vm.temps.isEmpty {
                Text(L10n.t("temp.none"))
                    .font(.caption)
                    .foregroundStyle(TCTheme.secondaryLabel)
            } else {
                let list = compact ? Array(vm.temps.prefix(4)) : vm.temps
                ForEach(list, id: \.key) { t in
                    HStack(spacing: DS.Space.s + 2) {
                        Text(label(for: t.key))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(TCTheme.secondaryLabel)
                            .frame(width: compact ? 64 : 78, alignment: .leading)
                            .lineLimit(1)
                        GeometryReader { geo in
                            let p = min(max((t.celsius - 20) / 90, 0), 1)
                            ZStack(alignment: .leading) {
                                Capsule().fill(TCTheme.controlFill)
                                Capsule()
                                    .fill(TCTheme.tempTint(t.celsius))
                                    .frame(width: max(8, geo.size.width * p))
                            }
                        }
                        .frame(height: 6)
                        Text("\(Int(t.celsius.rounded()))°")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .frame(width: 36, alignment: .trailing)
                            .foregroundStyle(TCTheme.tempTint(t.celsius))
                    }
                }
            }
        }
    }
}