import Foundation
import IOKit.ps

final class BatteryController {
    private let smc: any SMCProtocol
    private let lock = NSRecursiveLock()
    private var familyStore: BatteryFamily = .none
    private(set) var upper = 80
    private(set) var lower = 70
    private(set) var chargingEnabled = true
    private(set) var forceDischarge = false
    private(set) var maintainActive = false
    private(set) var lastError: String?
    private var inhibitByte: UInt8 = TC.chargeInhibitByteHigh
    private var chteSize: UInt32 = 4
    private var chteIsU8 = false
    private var suppressTickUntil = Date.distantPast
    private var hasCHTE = false
    private var hasCH0B = false
    private var hasCH0C = false
    private var hasCHIE = false

    init(smc: any SMCProtocol) { self.smc = smc }

    var family: BatteryFamily {
        lock.lock(); defer { lock.unlock() }
        return familyStore
    }

    func probe() {
        lock.lock(); defer { lock.unlock() }
        hasCHTE = smc.keyExists(SMCKey.chTE.rawValue)
        hasCHIE = smc.keyExists(SMCKey.chIE.rawValue)
        hasCH0B = smc.keyExists(SMCKey.ch0B.rawValue)
        hasCH0C = smc.keyExists(SMCKey.ch0C.rawValue)
        if hasCHTE || hasCHIE { familyStore = .tahoe }
        else if hasCH0B || hasCH0C { familyStore = .legacy }
        else { familyStore = .none }
        if let inf = try? smc.info(SMCKey.chTE.rawValue) {
            chteSize = max(1, inf.dataSize)
            chteIsU8 = inf.type == .ui8 || inf.dataSize <= 1
        }
    }

    var canControl: Bool {
        lock.lock(); defer { lock.unlock() }
        return familyStore != .none
    }

    func status() -> BatteryStatus {
        lock.lock(); defer { lock.unlock() }
        let io = readIOKit()
        let amps = (try? smc.readDouble(SMCKey.b0AC.rawValue)) ?? 0
        let volts = (try? smc.readDouble(SMCKey.b0AV.rawValue)) ?? 0
        return BatteryStatus(
            present: io.present, percent: io.percent, externalAC: io.ac,
            amperageMA: amps, voltageMV: volts,
            upperLimit: upper, lowerLimit: lower,
            chargingEnabled: chargingEnabled, maintainActive: maintainActive,
            forceDischarge: forceDischarge, keyFamily: familyStore.rawValue, lastError: lastError
        )
    }

    func suppressTick(seconds: TimeInterval = 1.2) {
        lock.lock(); defer { lock.unlock() }
        suppressTickUntil = Date().addingTimeInterval(seconds)
    }

    func setLimit(upper: Int, lower: Int) -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        guard canControl else { return (false, "Máy không có key sạc") }
        suppressTick(seconds: 1.2)
        let limits = ChargeLimits(upper: upper, lower: lower)
        self.upper = limits.upper
        self.lower = limits.lower
        maintainActive = true
        return applyImmediate(percent: status().percent)
    }

    func setChargingEnabled(_ enabled: Bool) -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        suppressTick(seconds: 1.2)
        maintainActive = false
        chargingEnabled = enabled
        if enabled {
            upper = 100
            lower = 95
        }
        return writeGate(enabled: enabled)
    }

    func setForceDischarge(_ enabled: Bool) -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        forceDischarge = enabled
        do {
            switch familyStore {
            case .legacy:
                if smc.keyExists(SMCKey.ch0I.rawValue) { try smc.writeUInt8(SMCKey.ch0I.rawValue, enabled ? 1 : 0, verify: false) }
            case .tahoe:
                if smc.keyExists(SMCKey.chIE.rawValue) { try smc.writeUInt8(SMCKey.chIE.rawValue, enabled ? 1 : 0, verify: false) }
            case .none:
                return (false, "Không hỗ trợ force discharge")
            }
            lastError = nil
            return (true, nil)
        } catch {
            lastError = "\(error)"
            return (false, lastError)
        }
    }

    func disableForceDischarge() {
        lock.lock(); defer { lock.unlock() }
        guard forceDischarge else { return }
        _ = setForceDischarge(false)
    }

    func tick() {
        lock.lock(); defer { lock.unlock() }
        guard Date() >= suppressTickUntil else { return }
        if maintainActive { _ = apply(percent: status().percent) }
        if forceDischarge { _ = setForceDischarge(true) }
    }

    func restoreDefaultCharge() {
        lock.lock(); defer { lock.unlock() }
        maintainActive = false
        forceDischarge = false
        _ = setForceDischarge(false)
        _ = writeGate(enabled: true)
        chargingEnabled = true
    }

    private func applyImmediate(percent: Int) -> (Bool, String?) {
        if percent >= upper {
            chargingEnabled = false
            return writeGate(enabled: false)
        }
        chargingEnabled = true
        return writeGate(enabled: true)
    }

    private func apply(percent: Int) -> (Bool, String?) {
        if percent >= upper { chargingEnabled = false; return writeGate(enabled: false) }
        if percent <= lower { chargingEnabled = true; return writeGate(enabled: true) }
        return writeGate(enabled: chargingEnabled)
    }

    private func writeTahoeInhibit(_ inhibit: Bool) throws {
        let n = Int(chteIsU8 ? 1 : max(4, chteSize))
        var payload = [UInt8](repeating: 0, count: n)
        payload[0] = inhibit ? 1 : 0
        var last: Error?
        for _ in 0..<3 {
            do {
                try smc.writeBytesDirect(SMCKey.chTE.rawValue, size: UInt32(n), payload)
                last = nil
                break
            } catch {
                last = error
            }
        }
        if let last { throw last }
    }

    // MARK: - DO NOT MODIFY (hardware timing)

    /// Charge-inhibit write sequence, reverse-engineered:
    ///   - tahoe: `CHTE`  big-endian payload (e.g. `01000000` when inhibiting)
    ///   - legacy: `CH0B`/`CH0C` = `TC.chargeInhibitByteHigh` (0x02), falling
    ///     back to `TC.chargeInhibitByteLow` (0x01) when B0AC still shows
    ///     charging current above `chargeTruthMA` after the 0.35s settle sleep.
    /// The sleeps, retry branches and byte values are load-bearing — reordering
    /// or converting these writes can stop the charge inhibit working on real
    /// hardware. (Refactor plan Phase 3 deliberately leaves this untouched.)
    ///
    /// `smc -k CHTE -w 01000000` to inhibit; also CH0B/CH0C 0x02 on machines that still have them.
    private func writeGate(enabled: Bool) -> (Bool, String?) {
        if forceDischarge && enabled {
            return (true, nil)
        }
        do {
            var wrote = false
            if hasCHTE {
                try writeTahoeInhibit(!enabled)
                wrote = true
            }
            if hasCH0B || hasCH0C {
                let v: UInt8 = enabled ? 0x00 : inhibitByte
                if hasCH0B { try smc.writeUInt8(SMCKey.ch0B.rawValue, v, verify: false) }
                if hasCH0C { try smc.writeUInt8(SMCKey.ch0C.rawValue, v, verify: false) }
                wrote = true
            }
            if !wrote {
                if familyStore == .none { return (false, "Không có battery control") }
                if hasCHIE, !enabled {
                    try smc.writeUInt8(SMCKey.chIE.rawValue, 1, verify: false)
                    wrote = true
                }
            }
            if !enabled {
                Thread.sleep(forTimeInterval: 0.35)
                let ma = (try? smc.readDouble(SMCKey.b0AC.rawValue)) ?? 0
                if ma > TC.chargeTruthMA {
                    if hasCHTE {
                        let n = Int(max(4, chteSize))
                        var be = [UInt8](repeating: 0, count: n)
                        be[n - 1] = 1
                        try? smc.writeBytesDirect(SMCKey.chTE.rawValue, size: UInt32(n), be)
                    }
                    if inhibitByte == TC.chargeInhibitByteHigh, hasCH0B || hasCH0C {
                        inhibitByte = TC.chargeInhibitByteLow
                        if hasCH0B { try? smc.writeUInt8(SMCKey.ch0B.rawValue, TC.chargeInhibitByteLow, verify: false) }
                        if hasCH0C { try? smc.writeUInt8(SMCKey.ch0C.rawValue, TC.chargeInhibitByteLow, verify: false) }
                    }
                }
            } else if hasCHIE {
                try? smc.writeUInt8(SMCKey.chIE.rawValue, 0, verify: false)
            }
            lastError = nil
            return (true, nil)
        } catch {
            lastError = "\(error)"
            return (false, lastError)
        }
    }

    private func readIOKit() -> (present: Bool, percent: Int, ac: Bool) {
        SensorReads.batteryIO()
    }
}
