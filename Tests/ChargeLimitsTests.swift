import XCTest
@testable import ThermalControl

final class ChargeLimitsTests: XCTestCase {
    func testClampsUpperToSafeBounds() {
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 70).upper, 80)
        XCTAssertEqual(ChargeLimits(upper: 120, lower: 70).upper, 99)
        XCTAssertEqual(ChargeLimits(upper: 5, lower: 2).upper, 40)
        XCTAssertEqual(ChargeLimits(upper: 100, lower: 95).upper, 99)
    }

    func testClampsLowerWithinPublishedDomain() {
        XCTAssertEqual(ChargeLimits(upper: 80, lower: -5).lower, 20)
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 0).lower, 20)
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 75).lower, 75)
    }

    func testEnforcesFivePercentGap() {
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 80).lower, 75)
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 79).lower, 75)
        XCTAssertEqual(ChargeLimits(upper: 99, lower: 98).lower, 94)
    }

    func testMinimumUpperNeverPushesLowerBelowDomain() {
        let limits = ChargeLimits(upper: 20, lower: 20)
        XCTAssertEqual(limits.upper, 40)
        XCTAssertEqual(limits.lower, 20)
    }

    func testDefaultsMatchUI() {
        XCTAssertEqual(ChargeLimits.defaults, ChargeLimits(upper: 80, lower: 70))
    }

    func testEquality() {
        XCTAssertEqual(ChargeLimits(upper: 80, lower: 30), ChargeLimits(upper: 80, lower: 30))
        XCTAssertNotEqual(ChargeLimits(upper: 80, lower: 30), ChargeLimits(upper: 79, lower: 30))
    }
}
