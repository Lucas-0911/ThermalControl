import Foundation
import IOKit.ps

final class BatteryController {
    typealias BatteryReader = () -> (present: Bool, percent: Int, ac: Bool)

    private let smc: any SMCProtocol
    private let batteryReader: BatteryReader
    private let monotonicNow: () -> TimeInterval
    private var dischargeTarget: Int?
    private var dischargeDeadline: TimeInterval?
    private var dischargeStopVerified = false
    private var dischargeStopReason: String?
    private var dischargeStopPending = false
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
    private var suppressTickUntil: TimeInterval = 0
    private var chargingApplied: Bool?
    private var hasCHTE = false
    private var hasCH0B = false
    private var hasCH0C = false
    private var hasCHIE = false

    init(
        smc: any SMCProtocol,
        batteryReader: @escaping BatteryReader = SensorReads.batteryIO,
        monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.smc = smc
        self.batteryReader = batteryReader
        self.monotonicNow = monotonicNow
    }

    var family: BatteryFamily {
        lock.lock(); defer { lock.unlock() }
        return familyStore
    }

    func probe() {
        lock.lock(); defer { lock.unlock() }
        chargingApplied = nil
        dischargeStopVerified = false
        dischargeTarget = nil
        dischargeDeadline = nil
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
        return hasCHTE || hasCH0B || hasCH0C
    }

    var canForceDischarge: Bool {
        lock.lock(); defer { lock.unlock() }
        return canControl && dischargeKey != nil
    }

    private var dischargeKey: String? {
        switch familyStore {
        case .tahoe: return hasCHIE ? SMCKey.chIE.rawValue : nil
        case .legacy: return smc.keyExists(SMCKey.ch0I.rawValue) ? SMCKey.ch0I.rawValue : nil
        case .none: return nil
        }
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
            forceDischarge: forceDischarge, keyFamily: familyStore.rawValue, lastError: lastError,
            canControlCharge: canControl, canForceDischarge: canForceDischarge,
            dischargeTargetPercent: dischargeTarget ?? -1,
            dischargeRemainingSeconds: dischargeDeadline.map { max(0, $0 - monotonicNow()) } ?? 0,
            dischargeStopVerified: dischargeStopVerified, dischargeStopReason: dischargeStopReason
        )
    }

    func suppressTick(seconds: TimeInterval = 1.2) {
        lock.lock(); defer { lock.unlock() }
        suppressTickUntil = monotonicNow() + max(0, seconds)
    }

    func setLimit(upper: Int, lower: Int) -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        guard canControl else { return (false, "Máy không có key charge-inhibit") }
        guard !forceDischarge, !dischargeStopPending else { return (false, "Dừng xả pin trước khi đổi giới hạn sạc") }
        let io = readIOKit()
        guard io.present, (0...100).contains(io.percent) else { return (false, "Dữ liệu pin không đáng tin cậy") }
        if dischargeKey != nil, !dischargeStopVerified {
            let stopped = stopForceDischarge()
            guard stopped.0 else { return stopped }
        }
        suppressTick(seconds: 1.2)
        let limits = ChargeLimits(upper: upper, lower: lower)
        let previous = (self.upper, self.lower, maintainActive, chargingEnabled)
        self.upper = limits.upper
        self.lower = limits.lower
        maintainActive = true
        let result = applyImmediate(percent: io.percent)
        if !result.0 {
            (self.upper, self.lower, maintainActive, chargingEnabled) = previous
        }
        return result
    }

    func setChargingEnabled(_ enabled: Bool) -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        guard canControl else { return (false, "Máy không có key charge-inhibit") }
        guard !forceDischarge, !dischargeStopPending else { return (false, "Dừng xả pin trước khi đổi trạng thái sạc") }
        if dischargeKey != nil, !dischargeStopVerified {
            let stopped = stopForceDischarge()
            guard stopped.0 else { return stopped }
        }
        suppressTick(seconds: 1.2)
        let previous = (upper, lower, maintainActive, chargingEnabled)
        maintainActive = false
        chargingEnabled = enabled
        if enabled {
            upper = 100
            lower = 95
        }
        let result = writeGate(enabled: enabled)
        if !result.0 {
            (upper, lower, maintainActive, chargingEnabled) = previous
        }
        return result
    }

    func setForceDischarge(_ enabled: Bool) -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return stopForceDischarge() }
        guard !dischargeStopPending else { return (false, "Chưa xác minh dừng phiên xả pin trước") }
        guard canForceDischarge, let key = dischargeKey else { return (false, "Không hỗ trợ force discharge an toàn") }
        guard maintainActive else { return (false, "Bật duy trì giới hạn sạc trước khi xả pin") }
        let io = readIOKit()
        guard io.present, (0...100).contains(io.percent), io.ac, io.percent > upper else {
            return (false, "Xả pin cần AC và mức pin đáng tin cậy cao hơn giới hạn trên")
        }
        // Repeating Start must not extend the helper-owned session deadline.
        if forceDischarge, !dischargeStopPending {
            if let deadline = dischargeDeadline, monotonicNow() < deadline { return (true, nil) }
            _ = stopForceDischarge(reason: "deadline")
            return (false, "Phiên xả pin đã hết hạn")
        }
        let stopped = stopForceDischarge()
        guard stopped.0 else { return stopped }
        dischargeStopVerified = false
        dischargeStopPending = true
        do {
            try smc.writeUInt8(key, 1, verify: true)
            guard try smc.readUInt8(key) == 1 else { throw SMCError.verify(key) }
            forceDischarge = true
            dischargeStopPending = false
            dischargeTarget = upper
            // ponytail: one session, hard 60-minute ceiling; add configurable policy only if required.
            dischargeDeadline = monotonicNow() + 60 * 60
            dischargeStopReason = nil
            chargingApplied = nil
            lastError = nil
            return (true, nil)
        } catch {
            let startError = "\(error)"
            // A throwing write may still have reached hardware. Do not claim Off without readback.
            forceDischarge = true
            let stopped = stopForceDischarge(reason: "startFailed")
            lastError = stopped.0 ? startError : "\(startError); \(stopped.1 ?? "Không xác minh được dừng xả pin")"
            return (false, lastError)
        }
    }

    @discardableResult
    func stopForceDischarge() -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        return stopForceDischarge(reason: "manual")
    }

    private func stopForceDischarge(reason: String) -> (Bool, String?) {
        dischargeStopReason = reason
        guard let key = dischargeKey else {
            if forceDischarge || dischargeStopPending {
                dischargeStopVerified = false
                lastError = "Không tìm thấy key để dừng xả pin"
                return (false, lastError)
            }
            dischargeStopVerified = true
            return (true, nil)
        }
        dischargeStopVerified = false
        dischargeStopPending = true
        do {
            // Always verify hardware; cached false is not proof after reset or a partial write.
            try smc.writeUInt8(key, 0, verify: true)
            guard try smc.readUInt8(key) == 0 else { throw SMCError.verify(key) }
            forceDischarge = false
            dischargeStopPending = false
            dischargeStopVerified = true
            dischargeTarget = nil
            dischargeDeadline = nil
            chargingApplied = nil
            lastError = nil
            return (true, nil)
        } catch {
            lastError = "Không xác minh được dừng xả pin: \(error)"
            return (false, lastError)
        }
    }

    func disableForceDischarge() {
        _ = stopForceDischarge()
    }

    func tick() {
        lock.lock(); defer { lock.unlock() }
        let io = readIOKit()
        if maintainActive && (!io.present || !(0...100).contains(io.percent)) {
            let restored = restoreDefaultCharge()
            dischargeStopReason = "untrustedIO"
            lastError = restored.0 ? "Dữ liệu pin không đáng tin cậy; đã khôi phục sạc mặc định"
                : "Dữ liệu pin không đáng tin cậy; \(restored.1 ?? "Khôi phục sạc thất bại")"
            return
        }
        if forceDischarge || dischargeStopPending {
            let reason: String?
            if dischargeStopPending { reason = dischargeStopReason ?? "stopRetry" }
            else if !io.present || !(0...100).contains(io.percent) { reason = "untrustedIO" }
            else if !io.ac { reason = "unplugged" }
            else if let deadline = dischargeDeadline, monotonicNow() >= deadline { reason = "deadline" }
            else if let target = dischargeTarget, io.percent <= target { reason = "targetReached" }
            else if dischargeDeadline == nil || dischargeTarget == nil { reason = "sessionMissing" }
            else { reason = nil }
            if let reason { _ = stopForceDischarge(reason: reason) }
            if forceDischarge || dischargeStopPending { return }
        }
        guard monotonicNow() >= suppressTickUntil, canControl,
              dischargeKey == nil || dischargeStopVerified,
              io.present, (0...100).contains(io.percent) else { return }
        if maintainActive { _ = apply(percent: io.percent) }
    }

    @discardableResult
    func restoreDefaultCharge() -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        let discharge = stopForceDischarge()
        guard discharge.0 else { return discharge }
        // CHIE alone is a discharge key, never a charge-inhibit capability.
        guard canControl else { return (true, nil) }
        let gate = writeGate(enabled: true)
        if gate.0 && dischargeStopVerified {
            maintainActive = false
            chargingEnabled = true
            upper = 100
            lower = 95
        }
        let errors = [discharge, gate].filter { !$0.0 }.map { $0.1 ?? "Restore failed" }
        if !errors.isEmpty { lastError = errors.joined(separator: "; ") }
        return (errors.isEmpty, errors.isEmpty ? nil : lastError)
    }

    private func applyImmediate(percent: Int) -> (Bool, String?) {
        let desired = percent < upper
        let result = writeGate(enabled: desired)
        if result.0 { chargingEnabled = desired }
        return result
    }

    private func apply(percent: Int) -> (Bool, String?) {
        let desired: Bool
        if percent >= upper { desired = false }
        else if percent <= lower { desired = true }
        else { return (true, nil) }
        guard chargingApplied != desired else { return (true, nil) }
        let result = writeGate(enabled: desired)
        if result.0 { chargingEnabled = desired }
        return result
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
    /// or converting these writes can stop charge inhibit on real hardware.
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
            chargingApplied = enabled
            lastError = nil
            return (true, nil)
        } catch {
            lastError = "\(error)"
            return (false, lastError)
        }
    }

    private func readIOKit() -> (present: Bool, percent: Int, ac: Bool) {
        batteryReader()
    }
}
