import Charts
import SwiftUI

enum TCTheme {
    static let mint = Color(red: 0.22, green: 0.90, blue: 0.78)
    static let cyan = Color(red: 0.38, green: 0.78, blue: 1.0)
    static let grape = Color(red: 0.67, green: 0.48, blue: 1.0)
    static let peach = Color(red: 1.0, green: 0.47, blue: 0.45)
    static let sun = Color(red: 1.0, green: 0.72, blue: 0.20)
    static let lime = Color(red: 0.58, green: 0.92, blue: 0.38)
    static let ink = Color.primary

    /// Light green → deep green → gold → orange → red (no blue/purple jump).
    static let fanHeatStops: [(Double, Double, Double, Double)] = [
        (0.00, 0.78, 0.96, 0.58),
        (0.16, 0.42, 0.86, 0.38),
        (0.32, 0.55, 0.80, 0.18),
        (0.48, 0.97, 0.82, 0.20),
        (0.64, 1.00, 0.58, 0.14),
        (0.80, 0.98, 0.32, 0.14),
        (1.00, 0.90, 0.12, 0.14)
    ]

    static func fanFillGradient(progress: Double) -> AngularGradient {
        let p = min(1, max(0.02, progress))
        var stops: [Gradient.Stop] = []
        for s in fanHeatStops where s.0 <= p + 0.0001 {
            let loc = min(1, s.0 / p)
            stops.append(.init(color: Color(red: s.1, green: s.2, blue: s.3), location: loc))
        }
        let end = fanTint(progress: p)
        if stops.last?.location ?? 0 < 1 {
            stops.append(.init(color: end, location: 1))
        }
        if stops.isEmpty {
            stops = [.init(color: end, location: 0), .init(color: end, location: 1)]
        }
        return AngularGradient(
            gradient: Gradient(stops: stops),
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(max(12, 360 * p - 1))
        )
    }

    static func fanTint(progress: Double) -> Color {
        let p = min(1, max(0, progress))
        let stops = fanHeatStops
        if p <= stops.first!.0 {
            return Color(red: stops[0].1, green: stops[0].2, blue: stops[0].3)
        }
        for i in 1..<stops.count {
            if p <= stops[i].0 {
                let a = stops[i - 1], b = stops[i]
                let t = (p - a.0) / max(0.0001, b.0 - a.0)
                return Color(
                    red: a.1 + (b.1 - a.1) * t,
                    green: a.2 + (b.2 - a.2) * t,
                    blue: a.3 + (b.3 - a.3) * t
                )
            }
        }
        let last = stops.last!
        return Color(red: last.1, green: last.2, blue: last.3)
    }

    static func tempTint(_ c: Double) -> Color {
        if c >= 95 { return peach }
        if c >= 80 { return sun }
        return cyan
    }
}

struct MiniCard<Content: View>: View {
    var tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [tint.opacity(0.16), tint.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(tint.opacity(0.28), lineWidth: 1)
            )
    }
}

struct ChoicePill: View {
    let title: String
    let symbol: String
    var selected = false
    var tint: Color
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                Text(title)
                    .font(.caption.weight(.bold))
                    .fontDesign(.rounded)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? .white : tint)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? tint : tint.opacity(0.14))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

struct PanelCard<Content: View>: View {
    let title: String
    var symbol: String
    var tint: Color = TCTheme.cyan
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                Spacer()
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = TCTheme.cyan
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.18), tint.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

struct ModeTile: View {
    let title: String
    let symbol: String
    var selected = false
    var tint: Color = TCTheme.cyan
    var enabled = true
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: compact ? 3 : 6) {
                Image(systemName: symbol)
                    .font((compact ? Font.body : Font.title2).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.caption.weight(.bold))
                    .fontDesign(.rounded)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 8 : 12)
            .foregroundStyle(selected ? .white : tint)
            .background(
                RoundedRectangle(cornerRadius: compact ? 12 : 16, style: .continuous)
                    .fill(selected ? tint : tint.opacity(0.12))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

struct ChipButton: View {
    let title: String
    var selected = false
    var tint: Color = TCTheme.lime
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .fontDesign(.rounded)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? .white : tint)
        .background(
            Capsule(style: .continuous)
                .fill(selected ? tint : tint.opacity(0.14))
        )
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

struct ConnectionDot: View {
    let connected: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? TCTheme.lime : TCTheme.sun)
                .frame(width: 8, height: 8)
                .shadow(color: (connected ? TCTheme.lime : TCTheme.sun).opacity(0.7), radius: 4)
            Text(connected ? L10n.t("online") : L10n.t("offline"))
                .font(.caption.weight(.bold))
                .fontDesign(.rounded)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct SoftNumberField: View {
    @Binding var value: Int
    var width: CGFloat = 72
    var enabled = true
    var onCommit: () -> Void = {}
    var onLive: () -> Void = {}

    var body: some View {
        KeyableIntField(value: $value, enabled: enabled, onCommit: onCommit, onLive: onLive)
            .frame(width: width, height: 28)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// NSTextField so the menu-bar extra can actually receive keypresses.
struct KeyableIntField: NSViewRepresentable {
    @Binding var value: Int
    var enabled: Bool
    var onCommit: () -> Void
    var onLive: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField(string: "\(value)")
        tf.delegate = context.coordinator
        tf.alignment = .center
        tf.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        tf.isBordered = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.formatter = nil
        return tf
    }

    func updateNSView(_ tf: NSTextField, context: Context) {
        context.coordinator.parent = self
        tf.isEnabled = enabled
        if tf.currentEditor() == nil, tf.stringValue != "\(value)" {
            tf.stringValue = "\(value)"
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: KeyableIntField
        init(_ parent: KeyableIntField) { self.parent = parent }

        func controlTextDidBeginEditing(_ obj: Notification) {
            NSApp.activate(ignoringOtherApps: true)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            apply(tf.stringValue, live: true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            apply(tf.stringValue, live: false)
            parent.onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) {
                apply(textView.string, live: false)
                parent.onCommit()
                return true
            }
            return false
        }

        private func apply(_ raw: String, live: Bool) {
            let digits = raw.filter(\.isNumber)
            guard let n = Int(digits) else { return }
            if parent.value != n { parent.value = n }
            if live { parent.onLive() }
        }
    }
}

struct ConfigNumberRow: View {
    let title: String
    var unit: String = ""
    @Binding var value: Int
    var tint: Color = TCTheme.cyan
    var enabled = true
    var onCommit: () -> Void = {}
    var onLive: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(.secondary)
            Spacer()
            SoftNumberField(
                value: $value,
                width: 76,
                enabled: enabled,
                onCommit: onCommit,
                onLive: onLive
            )
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(tint)
                    .frame(width: 36, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct PowerSparkline: View {
    let samples: [PowerSample]
    var maxWatts: Double
    var compact: Bool
    var title: String = L10n.t("power.chart")
    var tint: Color = TCTheme.sun

    private var domainStart: Date {
        (samples.last?.time ?? Date()).addingTimeInterval(-TC.powerHistoryWindow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = samples.last {
                    Text(String(format: "%.0fW", last.watts))
                        .font(.caption.weight(.heavy).monospacedDigit())
                        .fontDesign(.rounded)
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
                        colors: [tint.opacity(0.5), tint.opacity(0.05)],
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
                .lineStyle(StrokeStyle(lineWidth: compact ? 1.6 : 2.2, lineCap: .round))
            }
            .chartXScale(domain: domainStart...(samples.last?.time ?? Date()))
            .chartYScale(domain: 0...max(maxWatts, 8))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .frame(height: compact ? 44 : 72)
            .animation(.easeInOut(duration: 0.25), value: samples.last?.watts)
            .allowsHitTesting(false)
        }
    }
}

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
    private var size: CGFloat { compact ? 78 : 132 }
    private var ring: CGFloat { compact ? 11 : 15 }

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
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: ring, lineCap: .round))

                Circle()
                    .trim(from: 0, to: max(0.02, progress))
                    .stroke(
                        TCTheme.fanFillGradient(progress: progress),
                        style: StrokeStyle(lineWidth: ring, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Image(systemName: "fanblades.fill")
                        .font(compact ? .title3 : .title)
                        .foregroundStyle(tint)
                        .rotationEffect(.degrees(angle))
                    Text("\(Int(shownRPM.rounded()))")
                        .font(.system(size: compact ? 18 : 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text("RPM")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            Text(title)
                .font(.caption.weight(.bold))
                .fontDesign(.rounded)
            if !compact {
                Text("\(Int(minRPM)) – \(Int(maxRPM))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
