import Charts
import SwiftUI

/// Rolling 30s power/usage chart. Native restyle: secondary-label caption,
/// tint from the semantic palette, quiet plot background.
struct PowerSparkline: View {
    let samples: [PowerSample]
    var maxWatts: Double
    var compact: Bool
    var title: String = L10n.t("power.chart")
    var tint: Color = TCTheme.power

    private var domainStart: Date {
        (samples.last?.time ?? Date()).addingTimeInterval(-TC.powerHistoryWindow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TCTheme.secondaryLabel)
                Spacer()
                if let last = samples.last {
                    Text(String(format: "%.0fW", last.watts))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(tint)
                }
            }
            Chart(samples) { s in
                AreaMark(
                    x: .value("t", s.time),
                    y: .value("W", s.watts)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.35), tint.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("t", s.time),
                    y: .value("W", s.watts)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: compact ? 1.5 : 2, lineCap: .round))
            }
            .chartXScale(domain: domainStart...(samples.last?.time ?? Date()))
            .chartYScale(domain: 0...max(maxWatts, 8))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.background(
                    TCTheme.controlFill.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                )
            }
            .frame(height: compact ? 44 : 72)
            .animation(.easeInOut(duration: 0.25), value: samples.last?.watts)
            .allowsHitTesting(false)
        }
    }
}