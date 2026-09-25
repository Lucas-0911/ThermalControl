import Foundation

/// Charge-window clamping, extracted from `BatteryViewModel`/`ThermalViewModel`
/// so the bounds contract is one place and unit-testable.
///
/// Contract:
///   - upper clamps to `[40, 99]`
///   - lower clamps to `[20, upper-5]`
struct ChargeLimits: Equatable {
    static let minPercent = 20
    static let minUpper = 40
    static let maxPercent = 99
    static let minGap = 5

    let upper: Int
    let lower: Int

    init(upper: Int, lower: Int) {
        let u = Self.clampUpper(upper)
        self.upper = u
        self.lower = min(u - Self.minGap, max(Self.minPercent, lower))
    }

    /// Upper-bound-only clamp, used by input bindings before the full
    /// (upper, lower) pair is known.
    static func clampUpper(_ value: Int) -> Int {
        min(maxPercent, max(minUpper, value))
    }

    /// Defaults seen in the UI for a fresh install.
    static let defaults = ChargeLimits(upper: 80, lower: 70)
}