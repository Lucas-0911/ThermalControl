import SwiftUI

struct TempPanel: View {
    @EnvironmentObject var vm: ThermalViewModel
    var compact: Bool = true

    private static let names: [String: String] = [
        "Tp01": "CPU P1",
        "Tp05": "CPU P2",
        "Tp09": "CPU E",
        "Tp0D": "CPU P3",
        "Tp0H": "CPU P4",
        "Tp0L": "CPU E2",
        "Tp0T": "CPU E3",
        "Tp0b": "CPU P5",
        "Tp0f": "CPU P6",
        "TC0P": L10n.t("temp.cpu.prox"),
        "Tg05": "GPU 1",
        "Tg0D": "GPU 2",
        "Tg0L": "GPU 3",
        "Tg0T": "GPU 4",
        "Tg0b": "GPU die",
        "Tg0f": "GPU die 2",
        "Tg0P": L10n.t("temp.gpu.prox"),
        "Tg1F": "GPU",
        "Te05": "GPU",
        "Te0F": "GPU",
        "Te0P": "GPU",
        "Ts0P": L10n.t("temp.skin"),
        "Ts0G": L10n.t("temp.gpu.skin")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if compact {
                Label(L10n.t("temp"), systemImage: "thermometer.medium")
                    .font(.headline.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(TCTheme.peach)
            }
            if vm.temps.isEmpty {
                Text(L10n.t("temp.none")).font(.caption).foregroundStyle(.secondary)
            } else {
                let list = compact ? Array(vm.temps.prefix(4)) : vm.temps
                ForEach(list, id: \.key) { t in
                    HStack(spacing: 10) {
                        Text(Self.names[t.key] ?? t.key)
                            .font(.caption.weight(.semibold))
                            .fontDesign(.rounded)
                            .frame(width: compact ? 64 : 78, alignment: .leading)
                        GeometryReader { geo in
                            let p = min(max((t.celsius - 20) / 90, 0), 1)
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(TCTheme.tempTint(t.celsius))
                                    .frame(width: max(8, geo.size.width * p))
                            }
                        }
                        .frame(height: 8)
                        Text("\(Int(t.celsius.rounded()))°")
                            .font(.caption.weight(.heavy).monospacedDigit())
                            .fontDesign(.rounded)
                            .frame(width: 36, alignment: .trailing)
                            .foregroundStyle(TCTheme.tempTint(t.celsius))
                    }
                }
            }
        }
    }
}
