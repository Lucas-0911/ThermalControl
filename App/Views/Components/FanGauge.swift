import SwiftUI

/// Animated circular fan gauge. The heat-ramp progress encoding is functional
/// (green = idle → red = max) and stays; chrome is restyled native:
/// hairline track, label colors, no glow.
struct FanGauge: View {
    let title: String
    let rpm: Double
    let minRPM: Double
    let maxRPM: Double
    var compact: Bool = false

    @State private var shownRPM: Double = 0
    @State private var angle: Double = 0
    @State private var lastTick: Date = .now

    private var progress: Double {
        let span = max(1, maxRPM - minRPM)
        return min(1, max(0, (shownRPM - minRPM) / span))
    }

    private var tint: Color { TCTheme.fanTint(progress: progress) }
    private var size: CGFloat { compact ? 74 : 124 }
    private var ring: CGFloat { compact ? 9 : 12 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: false)) { context in
            gauge
                .onChange(of: context.date) { _, now in
                    tick(now)
                }
        }
        .allowsHitTesting(false)
        .onAppear {
            shownRPM = rpm
            lastTick = Date()
        }
        .onChange(of: rpm) { _, new in
            lastTick = Date()
            _ = new
        }
    }

    private var gauge: some View {
        VStack(spacing: DS.Space.s) {
            ZStack {
                Circle()
                    .stroke(TCTheme.controlFill, style: StrokeStyle(lineWidth: ring, lineCap: .round))

                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(
                        TCTheme.fanFillGradient(progress: progress),
                        style: StrokeStyle(lineWidth: ring, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: DS.Space.xxs) {
                    Image(systemName: "fanblades.fill")
                        .font(compact ? .subheadline : .title3)
                        .foregroundStyle(tint)
                        .rotationEffect(.degrees(angle))
                    Text("\(Int(shownRPM.rounded()))")
                        .font(.system(size: compact ? 16 : 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(TCTheme.label)
                    Text("RPM")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(TCTheme.tertiaryLabel)
                }
            }
            .frame(width: size, height: size)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TCTheme.secondaryLabel)
            if !compact {
                Text("\(Int(minRPM)) – \(Int(maxRPM))")
                    .font(.caption2)
                    .foregroundStyle(TCTheme.tertiaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tick(_ now: Date) {
        var dt = now.timeIntervalSince(lastTick)
        if dt <= 0 || dt > 0.1 { dt = 1.0 / 60.0 }
        lastTick = now
        let follow = 1 - exp(-dt / 0.42)
        shownRPM += (rpm - shownRPM) * follow
        let spin = max(shownRPM, 0)
        if spin > 30 {
            angle += dt * spin * 0.09
            if angle > 3600 { angle = angle.truncatingRemainder(dividingBy: 360) }
        }
    }
}