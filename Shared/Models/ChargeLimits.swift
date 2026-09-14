import Foundation

/// Charge-window clamping, extracted from `BatteryViewModel`/`ThermalViewModel`
/// so the bounds contract is one place and unit-testable.
///
/// Contract (unchanged behavior):
///   - upper clamps to `[20, 99]`
///   - lower clamps to `[20, upper-2]` (never within 2 of the upper bound)
struct ChargeLimits: Equatable {
    static let minPercent = 20
    static let maxPercent = 99
    static let minGap = 2

    let upper: Int
    let lower: Int

    init(upper: Int, lower: Int) {
        let u = min(Self.maxPercent, max(Self.minPercent, upper))
        self.upper = u
        self.lower = min(u - Self.minGap, max(Self.minPercent, lower))
    }

    /// Defaults seen in the UI for a fresh install.
    static let defaults = ChargeLimits(upper: 80, lower: 70)
}