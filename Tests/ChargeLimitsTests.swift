import XCTest
@testable import ThermalControl

/// Guards the charge-window clamp contract that used to live inline in the
/// app's view model (and helper): upper ∈ [20,99], lower ∈ [20, upper-2].
final class ChargeLimitsTests: XCTestCase {
    func testClampsUpperToBounds() {
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 70).upper, 80)
        XCTAssertEqual(ChargeLimits(upper: 120, lower: 70).upper, 99)
        XCTAssertEqual(ChargeLimits(upper: 5, lower: 2).upper, 20)
        XCTAssertEqual(ChargeLimits(upper: 100, lower: 95).upper, 99)
    }

    func testClampsLowerWithinBounds() {
        XCTAssertEqual(ChargeLimits(upper: 80, lower: -5).lower, 20)
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 0).lower, 20)
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 78).lower, 78)
    }

    func testLowerNeverWithinTwoOfUpper() {
        // upper-2 is the floor for lower when the requested lower would collide.
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 80).lower, 78)
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 79).lower, 78)
        XCTAssertEqual(ChargeLimits(upper: 99, lower: 98).lower, 97)
    }

    /// Edge case inherited from the original VM/helper formula
    /// `min(upper-2, max(20, lower))`: at upper=20 the gap rule wins and lower
    /// lands BELOW minPercent (18). This is the shipped behavior — documented,
    /// not "fixed", because the clamp contract is frozen.
    func testEdgeAtMinimum() {
        let limits = ChargeLimits(upper: 20, lower: 20)
        XCTAssertEqual(limits.upper, 20)
        XCTAssertEqual(limits.lower, 18)
    }

    func testDefaultsMatchUI() {
        XCTAssertEqual(ChargeLimits.defaults, ChargeLimits(upper: 80, lower: 70))
    }

    func testEquality() {
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 30), ChargeLimits(upper: 80, lower: 30))
        XCTAssertNotEqual(ChargeLimits(upper: 80, lower: 30), ChargeLimits(upper: 79, lower: 30))
    }
}