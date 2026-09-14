import XCTest
@testable import ThermalControl

/// Codable round-trip + forward/backward compatibility of the helper's
/// on-disk policy state. File I/O lives in `StateStore` (helper process);
/// we only exercise the shape here so no root privileges are needed.
final class PersistedStateTests: XCTestCase {
    private func sample() -> PersistedState {
        PersistedState(
            fanMode: 3,
            manualRPM: 2500,
            maintain: true,
            upper: 80,
            lower: 70,
            chargingEnabled: true,
            forceDischarge: false,
            persistEnabled: true
        )
    }

    func testRoundTrip() throws {
        let encoded = try JSONEncoder().encode(sample())
        let decoded = try JSONDecoder().decode(PersistedState.self, from: encoded)
        XCTAssertEqual(decoded, sample())
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    /// Files written before `schemaVersion` existed (or a future default) must
    /// decode with the default value — `JSONDecoder` ignores unknown keys and
    /// synthesized CodingKeys use `decodeIfPresent` with the default.
    func testMissingSchemaVersionDefaultsTo1() throws {
        let legacyJSON = """
        {"fanMode":2,"manualRPM":1200,"maintain":false,"upper":80,"lower":70,
         "chargingEnabled":true,"forceDischarge":false,"persistEnabled":true}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PersistedState.self, from: legacyJSON)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.fanMode, 2)
        XCTAssertEqual(decoded.manualRPM, 1200)
    }

    /// A wrong-typed field makes decode throw — at the store layer a decode
    /// failure means "no persisted state", which is the fail-closed behavior.
    func testWrongTypeFailsClosed() {
        let badJSON = #"{"fanMode":"quiet","manualRPM":0,"maintain":true}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(PersistedState.self, from: badJSON))
    }

    func testAllFieldsRoundTripAtomically() throws {
        var s = sample()
        s.schemaVersion = 2
        s.fanMode = 0
        s.forceDischarge = true
        let decoded = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }
}