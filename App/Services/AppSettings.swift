import Foundation

/// Typed access to the app's `UserDefaults` keys. Replaces the magic strings
/// that were scattered through `ThermalViewModel` (`"savedChargeUpper"`
/// appeared at three call sites) and `LanguageSettings`.
enum AppSettings {
    enum Key {
        static let manualRPM = "manualRPM"
        static let fanDrafts = "fanDrafts"
        static let chargeUpper = "chargeUpper"
        static let chargeLower = "chargeLower"
        static let savedChargeUpper = "savedChargeUpper"
        static let chargeMode = "chargeMode"
        static let appLanguage = "appLanguage"
    }

    private static let defaults = UserDefaults.standard

    /// 0 when unset — callers keep their own default in that case
    /// (matches the original `d.integer(forKey:)` semantics).
    static var manualRPM: Int {
        get { defaults.integer(forKey: Key.manualRPM) }
        set { defaults.set(newValue, forKey: Key.manualRPM) }
    }

    /// Per-fan Custom RPM values keyed by fan index. Persisted so switching
    /// fan modes (or relaunching) no longer loses the user's configuration —
    /// previously drafts lived only in memory and Custom re-seeded from the
    /// previous mode's actual RPM. Stored as `[String: Int]` (plist-safe).
    static var fanDrafts: [Int: Int] {
        get {
            guard let raw = defaults.dictionary(forKey: Key.fanDrafts) as? [String: Int] else { return [:] }
            var out: [Int: Int] = [:]
            for (k, v) in raw {
                if let idx = Int(k) { out[idx] = v }
            }
            return out
        }
        set {
            var raw: [String: Int] = [:]
            for (k, v) in newValue { raw[String(k)] = v }
            defaults.set(raw, forKey: Key.fanDrafts)
        }
    }

    /// `nil` when never written — the original code distinguished
    /// "no value" (`object(forKey:) as? Int`) from a stored 0.
    static var chargeUpper: Int? {
        get { defaults.object(forKey: Key.chargeUpper) as? Int }
        set { defaults.set(newValue, forKey: Key.chargeUpper) }
    }

    static var chargeLower: Int? {
        get { defaults.object(forKey: Key.chargeLower) as? Int }
        set { defaults.set(newValue, forKey: Key.chargeLower) }
    }

    static var savedChargeUpper: Int {
        get { defaults.integer(forKey: Key.savedChargeUpper) }
        set { defaults.set(newValue, forKey: Key.savedChargeUpper) }
    }

    static var chargeMode: String? {
        get { defaults.string(forKey: Key.chargeMode) }
        set { defaults.set(newValue, forKey: Key.chargeMode) }
    }

    static var appLanguage: String? {
        get { defaults.string(forKey: Key.appLanguage) }
        set { defaults.set(newValue, forKey: Key.appLanguage) }
    }
}