import SwiftUI

/// Animated circular fan gauge.
/// Redesigned with Apple HIG arc styling, monospaced digits, and smooth rotation.
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
    private var size: CGFloat { compact ? 82 : 130 }
    private var ringWidth: CGFloat { compact ? 8 : 11 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: false)) { context in
            gaugeContent
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

    private var gaugeContent: some View {
        VStack(spacing: DS.Space.xs + 2) {
            ZStack {
                // Background Track
                Circle()
                    .stroke(
                        Color(nsColor: .separatorColor).opacity(0.18),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )

                // Heat Progress Arc
                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(
                        TCTheme.fanFillGradient(progress: progress),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: progress)

                // Center Telemetry: Icon + RPM
                VStack(spacing: 1) {
                    Image(systemName: "fanblades.fill")
                        .font(compact ? .system(size: 13, weight: .semibold) : .system(size: 20, weight: .semibold))
                        .foregroundStyle(tint)
                        .rotationEffect(.degrees(angle))
                        .shadow(color: tint.opacity(0.3), radius: compact ? 2 : 4, x: 0, y: 1)
                    
                    Text("\(Int(shownRPM.rounded()))")
                        .font(.system(size: compact ? 15 : 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(TCTheme.label)
                    
                    Text("RPM")
                        .font(.system(size: compact ? 8 : 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(TCTheme.tertiaryLabel)
                }
            }
            .frame(width: size, height: size)

            Text(title)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(TCTheme.secondaryLabel)
            
            if !compact {
                Text("\(Int(minRPM)) – \(Int(maxRPM)) RPM")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(TCTheme.tertiaryLabel)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tick(_ now: Date) {
        var dt = now.timeIntervalSince(lastTick)
        if dt <= 0 || dt > 0.1 { dt = 1.0 / 60.0 }
        lastTick = now
        let follow = 1 - exp(-dt / 0.35)
        shownRPM += (rpm - shownRPM) * follow
        let spin = max(shownRPM, 0)
        if spin > 30 {
            angle += dt * spin * 0.08
            if angle > 3600 { angle = angle.truncatingRemainder(dividingBy: 360) }
        }
    }
}
