import SwiftUI

struct TempPanel: View {
    @EnvironmentObject var vm: ThermalViewModel
    var compact: Bool = true

    private static let coreNames: [String: String] = [
        "Tp01": "CPU P1",
        "Tp05": "CPU P2",
        "Tp09": "CPU E1",
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
        "Tg0b": "GPU Die",
        "Tg0f": "GPU Die 2",
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
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            if compact {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TCTheme.temperature)
                    Text(L10n.t("temp").uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(TCTheme.secondaryLabel)
                    Spacer()
                }
            }

            if vm.temps.isEmpty {
                HStack {
                    Image(systemName: "slash.circle")
                        .foregroundStyle(TCTheme.secondaryLabel)
                    Text(L10n.t("temp.none"))
                        .font(.caption)
                        .foregroundStyle(TCTheme.secondaryLabel)
                }
                .padding(.vertical, 4)
            } else {
                let list = compact ? Array(vm.temps.prefix(4)) : vm.temps
                VStack(spacing: 8) {
                    ForEach(list, id: \.key) { t in
                        HStack(spacing: DS.Space.s + 2) {
                            Text(label(for: t.key))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(TCTheme.secondaryLabel)
                                .frame(width: compact ? 70 : 90, alignment: .leading)
                                .lineLimit(1)

                            // Subtle heat bar
                            GeometryReader { geo in
                                let p = min(max((t.celsius - 25) / 80, 0), 1)
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color(nsColor: .separatorColor).opacity(0.18))
                                    Capsule()
                                        .fill(TCTheme.tempTint(t.celsius))
                                        .frame(width: max(6, geo.size.width * p))
                                }
                            }
                            .frame(height: 5)

                            Text("\(Int(t.celsius.rounded()))°C")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                                .foregroundStyle(TCTheme.tempTint(t.celsius))
                        }
                    }
                }
            }
        }
    }
}
