import XCTest
@testable import ThermalControl

final class FanStatusTests: XCTestCase {
    func testTransitionStatusSecureCodingRoundTrip() throws {
        let fan = FanChannel(index: 0, actualRPM: 2_100, targetRPM: 2_125,
            minRPM: 1_200, maxRPM: 6_000, modeRaw: 1, modeKey: "F0Md", goalRPM: 4_000)
        let status = FanStatus(fans: [fan], desiredMode: FanMode.max.rawValue,
            ftstPresent: true, ramping: true, transitionID: 42)
        let data = try NSKeyedArchiver.archivedData(withRootObject: status, requiringSecureCoding: true)
        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: FanStatus.self, from: data))
        XCTAssertTrue(decoded.ramping)
        XCTAssertEqual(decoded.transitionID, 42)
        XCTAssertEqual(decoded.fans.first?.goalRPM, 4_000)
        XCTAssertEqual(decoded.fans.first?.targetRPM, 2_125)
        XCTAssertEqual(decoded.fans.first?.actualRPM, 2_100)
    }
}
