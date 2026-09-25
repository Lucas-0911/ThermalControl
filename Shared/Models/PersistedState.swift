import Foundation

/// Policy state the helper persists to disk and restores on daemon boot.
/// Lives in `Shared/` so the unit-test target can exercise the Codable
/// round-trip without touching `/Library/...` or the root daemon.
struct PersistedState: Codable, Equatable {
    /// Bump when the on-disk shape changes. Older files written before this
    /// field existed decode with it missing → defaults to 1 (see custom
    /// `init(from:)`; Swift's synthesized decoder would throw instead).
    var schemaVersion: Int = 1
    var fanMode: Int
    var manualRPM: Int
    var maintain: Bool
    var upper: Int
    var lower: Int
    var chargingEnabled: Bool
    var forceDischarge: Bool
    var persistEnabled: Bool

    init(
        schemaVersion: Int = 1,
        fanMode: Int,
        manualRPM: Int,
        maintain: Bool,
        upper: Int,
        lower: Int,
        chargingEnabled: Bool,
        forceDischarge: Bool,
        persistEnabled: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.fanMode = fanMode
        self.manualRPM = manualRPM
        self.maintain = maintain
        self.upper = upper
        self.lower = lower
        self.chargingEnabled = chargingEnabled
        self.forceDischarge = forceDischarge
        self.persistEnabled = persistEnabled
    }

    /// Transient hardware overrides must never survive a helper crash/restart.
    var safeForPersistence: PersistedState {
        var copy = self
        copy.forceDischarge = false
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, fanMode, manualRPM, maintain
        case upper, lower, chargingEnabled, forceDischarge, persistEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        fanMode = try c.decode(Int.self, forKey: .fanMode)
        manualRPM = try c.decode(Int.self, forKey: .manualRPM)
        maintain = try c.decode(Bool.self, forKey: .maintain)
        upper = try c.decode(Int.self, forKey: .upper)
        lower = try c.decode(Int.self, forKey: .lower)
        chargingEnabled = try c.decode(Bool.self, forKey: .chargingEnabled)
        forceDischarge = try c.decode(Bool.self, forKey: .forceDischarge)
        persistEnabled = try c.decode(Bool.self, forKey: .persistEnabled)
    }
}