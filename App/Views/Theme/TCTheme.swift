import SwiftUI

/// Semantic palette for the macOS-native redesign (Phase 5 & HIG overhaul).
/// Strictly dynamic system colors adapting to Light/Dark Mode & system accent.
enum TCTheme {
    // MARK: - Semantic accents

    static let fan = Color(nsColor: .systemBlue)
    static let battery = Color(nsColor: .systemGreen)
    static let temperature = Color(nsColor: .systemOrange)
    static let power = Color(nsColor: .systemYellow)
    static let quiet = Color(nsColor: .systemPurple)
    static let danger = Color(nsColor: .systemRed)
    static let charge = Color(nsColor: .systemTeal)
    static let accent = Color(nsColor: .controlAccentColor)

    // MARK: - Surfaces & Labels (Native macOS)

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let label = Color(nsColor: .labelColor)
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)
    static let quaternaryLabel = Color(nsColor: .quaternaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)

    /// Native control fill
    static let controlFill = Color(nsColor: .controlColor)
    static let fieldFill = Color(nsColor: .textBackgroundColor)

    // MARK: - Functional heat ramp

    static let fanHeatStops: [(Double, Color)] = [
        (0.00, Color(nsColor: .systemGreen)),
        (0.45, Color(nsColor: .systemYellow)),
        (0.72, Color(nsColor: .systemOrange)),
        (1.00, Color(nsColor: .systemRed)),
    ]

    static func fanTint(progress: Double) -> Color {
        rampColor(at: min(1, max(0, progress)), stops: fanHeatStops)
    }

    static func fanFillGradient(progress: Double) -> AngularGradient {
        let p = min(1, max(0.02, progress))
        var stops: [Gradient.Stop] = []
        for (loc, color) in fanHeatStops where loc <= p + 0.0001 {
            stops.append(.init(color: color, location: min(1, loc / p)))
        }
        let end = fanTint(progress: p)
        if (stops.last?.location ?? 0) < 1 {
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

    static func tempTint(_ c: Double) -> Color {
        if c >= 95 { return danger }
        if c >= 80 { return temperature }
        if c >= 65 { return power }
        return charge
    }

    private static func rampColor(at p: Double, stops: [(Double, Color)]) -> Color {
        if p <= stops[0].0 { return stops[0].1 }
        for i in 1..<stops.count {
            if p <= stops[i].0 {
                let a = stops[i - 1], b = stops[i]
                let t = (p - a.0) / max(0.0001, b.0 - a.0)
                return interpolate(a.1, b.1, t: t)
            }
        }
        return stops[stops.count - 1].1
    }

    private static func interpolate(_ a: Color, _ b: Color, t: Double) -> Color {
        let ca = NSColor(a).usingColorSpace(.sRGB) ?? .blue
        let cb = NSColor(b).usingColorSpace(.sRGB) ?? .blue
        return Color(
            red: ca.redComponent + (cb.redComponent - ca.redComponent) * t,
            green: ca.greenComponent + (cb.greenComponent - ca.greenComponent) * t,
            blue: ca.blueComponent + (cb.blueComponent - ca.blueComponent) * t
        )
    }
}
