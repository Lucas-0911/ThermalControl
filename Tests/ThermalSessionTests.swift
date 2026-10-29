import XCTest
@testable import ThermalControl

@MainActor
final class ThermalSessionTests: XCTestCase {
    func testVisibilityStopsPowerSamplingAndRepeatedStartDoesNotDuplicateTimers() {
        let session = ThermalSession()
        var samples = 0
        var refreshes = 0
        session.onPowerSample = { samples += 1 }
        session.onRefresh = { refreshes += 1 }
        session.start()
        defer { session.stop() }
        session.start()
        XCTAssertEqual(session.activeTimerCountForTesting, 2)
        XCTAssertEqual(samples, 0)
        session.setVisibility(dashboard: true)
        XCTAssertEqual(session.activeTimerCountForTesting, 3)
        XCTAssertEqual(samples, 1)
        XCTAssertEqual(refreshes, 1)
        session.setVisibility(dashboard: true)
        XCTAssertEqual(samples, 1)
        XCTAssertEqual(refreshes, 1)
        session.setVisibility(dashboard: false)
        XCTAssertEqual(session.activeTimerCountForTesting, 2)
        session.setVisibility(menu: true)
        XCTAssertEqual(session.activeTimerCountForTesting, 2)
        XCTAssertEqual(samples, 1, "Menu must not start dashboard power sampling")
        session.pause()
        XCTAssertEqual(session.activeTimerCountForTesting, 0)
        session.resume()
        XCTAssertEqual(session.activeTimerCountForTesting, 2)
        session.stop()
        XCTAssertEqual(session.activeTimerCountForTesting, 0)
        XCTAssertFalse(session.started)
    }
}
