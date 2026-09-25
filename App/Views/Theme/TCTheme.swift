import SwiftUI

/// Semantic palette for the macOS-native redesign (Phase 5).
///
/// All colors are dynamic `NSColor` system colors: they adapt automatically
/// to light/dark appearance and to the user's accent-color preference, which
/// is what makes the app feel native instead of "custom-skinned".
enum TCTheme {
    // MARK: - Semantic accents

    /// Fan section / cool temps.
    static let fan = Color(nsColor: .systemBlue)
    /// Battery section / charging.
    static let battery = Color(nsColor: .systemGreen)
    /// Temperature section / warm.
    static let temperature = Color(nsColor: .systemOrange)
    /// Power / wattage / Custom fan mode.
    static let power = Color(nsColor: .systemYellow)
    /// Quiet mode.
    static let quiet = Color(nsColor: .systemPurple)
    /// Max mode / force discharge / hot temps.
    static let danger = Color(nsColor: .systemRed)
    /// Charge lower bound / teal accents.
    static let charge = Color(nsColor: .systemTeal)
    /// Auto mode — follows the user's system accent.
    static let accent = Color(nsColor: .controlAccentColor)

    // MARK: - Surfaces & labels

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let label = Color(nsColor: .labelColor)
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)
    static let separator = Color(nsColor: .separatorColor)

    /// Neutral control fill (unselected tiles/pills, tracks).
    static let controlFill = Color.primary.opacity(0.05)
    /// Slightly stronger neutral fill (input fields).
    static let fieldFill = Color.primary.opacity(0.07)

    // MARK: - Functional heat ramp

    /// Cool green → amber → hot red. Functional color scale for the fan
    /// gauge: encodes "how hard is the fan working", kept from the original
    /// design but re-tuned to sit well on both light and dark backgrounds.
    static let fanHeatStops: [(Double, Color)] = [
        (0.00, Color(red: 0.20, green: 0.78, blue: 0.35)),
        (0.45, Color(red: 0.98, green: 0.82, blue: 0.20)),
        (0.72, Color(red: 0.99, green: 0.55, blue: 0.13)),
        (1.00, Color(red: 0.90, green: 0.22, blue: 0.18)),
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

    /// Temperature bar color: cool → warm → hot.
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