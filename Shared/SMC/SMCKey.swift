import Foundation

/// Single source of truth for every SMC four-char key the app knows about.
///
/// Previously these literal strings were interleaved across `Constants.tempKeys`,
/// `SensorReader`, `FanController`, `BatteryController`, `SafetyWatchdog` and
/// `TempPanel.names` — five-plus sites with diverging subsets. The `rawValue`
/// MUST stay byte-identical to the AppleSMC key (SMCKeyTests guards this);
/// these are reverse-engineered hardware names, not free-form labels.
public struct SMCKey: Equatable, Hashable, CustomStringConvertible, Sendable {
    public let rawValue: String

    public init(_ raw: String) {
        rawValue = raw
    }

    public var description: String { rawValue }

    /// Big-endian FourCharCode — the same encoding `SMCService` uses on both
    /// Apple silicon and Intel.
    public var fourCC: UInt32 {
        var s = rawValue
        while s.utf8.count < 4 { s.append(" ") }
        return s.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }
}

public extension SMCKey {
    // MARK: - Fan

    static let fanCount = SMCKey("FNum")
    static func fanActual(_ index: Int) -> SMCKey { SMCKey("F\(index)Ac") }
    static func fanTarget(_ index: Int) -> SMCKey { SMCKey("F\(index)Tg") }
    static func fanMin(_ index: Int) -> SMCKey { SMCKey("F\(index)Mn") }
    static func fanMax(_ index: Int) -> SMCKey { SMCKey("F\(index)Mx") }
    /// Uppercase manual-mode key — the common form.
    static func fanMode(_ index: Int) -> SMCKey { SMCKey("F\(index)Md") }
    /// Lowercase manual-mode key — present on some Intel machines.
    static func fanModeLower(_ index: Int) -> SMCKey { SMCKey("F\(index)md") }

    // MARK: - FTST unlock (needed to force a fan into manual mode)

    static let ftst = SMCKey("FTST")
    static let ftstLower = SMCKey("Ftst")

    // MARK: - Battery telemetry

    static let b0AC = SMCKey("B0AC") // current in mA
    static let b0AV = SMCKey("B0AV") // voltage in mV

    // MARK: - Charge inhibit (family-specific)

    /// Legacy Apple Silicon family (CH0B/CH0C pair). `0x02` then `0x01` fallback.
    static let ch0B = SMCKey("CH0B")
    static let ch0C = SMCKey("CH0C")
    static let ch0I = SMCKey("CH0I") // legacy force-discharge
    /// "Tahoe" family (CHTE/CHIE). CHTE takes a big-endian inhibit byte.
    static let chTE = SMCKey("CHTE")
    static let chIE = SMCKey("CHIE")

    // MARK: - Temperature

    static let tp01 = SMCKey("Tp01")
    static let tp05 = SMCKey("Tp05")
    static let tp09 = SMCKey("Tp09")
    static let tp0D = SMCKey("Tp0D")
    static let tp0H = SMCKey("Tp0H")
    static let tp0L = SMCKey("Tp0L")
    static let tp0T = SMCKey("Tp0T")
    static let tp0b = SMCKey("Tp0b")
    static let tp0f = SMCKey("Tp0f")
    static let tc0P = SMCKey("TC0P")
    static let tg05 = SMCKey("Tg05")
    static let tg0D = SMCKey("Tg0D")
    static let tg0L = SMCKey("Tg0L")
    static let tg0T = SMCKey("Tg0T")
    static let tg0b = SMCKey("Tg0b")
    static let tg0f = SMCKey("Tg0f")
    static let tg0P = SMCKey("Tg0P")
    static let tg1F = SMCKey("Tg1F")
    static let te05 = SMCKey("Te05")
    static let te0F = SMCKey("Te0F")
    static let te0P = SMCKey("Te0P")
    static let ts0P = SMCKey("Ts0P")
    static let ts0G = SMCKey("Ts0G")

    /// Full temp set surfaced by the app (was `TC.tempKeys`).
    static let tempKeys: [SMCKey] = [
        .tp01, .tp05, .tp09, .tp0D, .tp0H, .tp0L, .tp0T, .tp0b, .tp0f,
        .tc0P,
        .tg05, .tg0D, .tg0L, .tg0T, .tg0b, .tg0f, .tg0P, .tg1F,
        .te05, .te0F, .te0P,
        .ts0P, .ts0G,
    ]

    /// Hotspot CPU/GPU keys watched by `SafetyWatchdog.enforceThermal`.
    /// Kept here so the safety trip keys are derived from the same source
    /// instead of a second, manually-maintained literal array.
    static let thermalTripKeys: [SMCKey] = [.tp01, .tp05, .tp09, .tp0D, .tc0P, .te05, .ts0P]
}