import Foundation
import os

final class FanController {
    private let smc: any SMCProtocol
    private let lock = NSLock()
    private var policyStore: FanPolicy = .system
    private(set) var lastError: String?
    private(set) var ftstPresent = false
    private var modeKeys: [Int: String] = [:]
    private var fanCount = 0
    private var ftstKey: String?
    private var ftstHeld = false

    init(smc: any SMCProtocol) { self.smc = smc }

    var policy: FanPolicy {
        lock.lock(); defer { lock.unlock() }
        return policyStore
    }

    var canControl: Bool { fanCount > 0 && !modeKeys.isEmpty }
    var count: Int { fanCount }

    func probe() {
        lock.lock(); defer { lock.unlock() }
        fanCount = Int((try? smc.readUInt8(SMCKey.fanCount.rawValue)) ?? 0)
        if smc.keyExists(SMCKey.ftstLower.rawValue) {
            ftstKey = SMCKey.ftstLower.rawValue
        } else if smc.keyExists(SMCKey.ftst.rawValue) {
            ftstKey = SMCKey.ftst.rawValue
        } else {
            ftstKey = nil
        }
        ftstPresent = ftstKey != nil
        modeKeys.removeAll()
        for i in 0..<fanCount {
            if smc.keyExists(SMCKey.fanMode(i).rawValue) { modeKeys[i] = SMCKey.fanMode(i).rawValue }
            else if smc.keyExists(SMCKey.fanModeLower(i).rawValue) { modeKeys[i] = SMCKey.fanModeLower(i).rawValue }
        }
    }

    func status() -> FanStatus {
        lock.lock(); defer { lock.unlock() }
        return statusUnlocked()
    }

    func setMode(_ mode: FanMode) -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        switch mode {
        case .system: return restoreSystemUnlocked()
        case .quiet: policyStore = .quiet; return applyUnlocked()
        case .max: policyStore = .max; return applyUnlocked()
        case .manual: return (false, "Dùng Set RPM cho Manual")
        }
    }

    func setManual(rpm: Int, index: Int) -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        var targets: [Int: Int] = [:]
        if case .manual(let existing) = policyStore {
            targets = existing
        }
        if index < 0 {
            for i in 0..<fanCount { targets[i] = rpm }
        } else {
            targets[index] = rpm
            if targets.count < fanCount {
                for i in 0..<fanCount where targets[i] == nil {
                    targets[i] = rpm
                }
            }
        }
        policyStore = .manual(targets: targets)
        return applyUnlocked()
    }

    @discardableResult
    func restoreSystem() -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        return restoreSystemUnlocked()
    }

    @discardableResult
    func apply() -> (Bool, String?) {
        lock.lock(); defer { lock.unlock() }
        return applyUnlocked()
    }

    private func statusUnlocked() -> FanStatus {
        var ch: [FanChannel] = []
        for i in 0..<fanCount {
            let key = modeKeys[i] ?? SMCKey.fanMode(i).rawValue
            ch.append(SensorReads.fanChannel(index: i, modeKey: key, smc: smc))
        }
        let mode: Int
        switch policyStore {
        case .system: mode = FanMode.system.rawValue
        case .quiet: mode = FanMode.quiet.rawValue
        case .max: mode = FanMode.max.rawValue
        case .manual: mode = FanMode.manual.rawValue
        }
        return FanStatus(fans: ch, desiredMode: mode, ftstPresent: ftstPresent, lastError: lastError)
    }

    private func restoreSystemUnlocked() -> (Bool, String?) {
        policyStore = .system
        lastError = nil
        do {
            for i in 0..<fanCount {
                if let key = modeKeys[i] { try smc.writeUInt8(key, 0, verify: false) }
            }
            releaseFtst()
            return (true, nil)
        } catch {
            lastError = "\(error)"
            return (false, lastError)
        }
    }

    private func applyUnlocked() -> (Bool, String?) {
        switch policyStore {
        case .system: return restoreSystemUnlocked()
        case .quiet: return force { Int($0.minRPM.rounded()) }
        case .max: return force { Int($0.maxRPM.rounded()) }
        case .manual(let targets):
            return force { ch in
                targets[ch.index] ?? targets.sorted(by: { $0.key < $1.key }).first?.value ?? Int(ch.minRPM.rounded())
            }
        }
    }

    private func force(rpm: (FanChannel) -> Int) -> (Bool, String?) {
        let snap = statusUnlocked()
        do {
            for ch in snap.fans {
                try enterManual(ch.index)
                let lo = Int(ch.minRPM.rounded())
                let hi = max(lo, Int(ch.maxRPM.rounded()))
                let target = min(max(rpm(ch), lo), hi)
                try smc.writeDouble(SMCKey.fanTarget(ch.index).rawValue, Double(target), verify: false)
            }
            lastError = nil
            return (true, nil)
        } catch {
            lastError = "\(error)"
            return (false, lastError)
        }
    }

    // MARK: - DO NOT MODIFY (hardware timing)

    /// FTST unlock + forced-mode sequence. The unlock-before-sleep in
    /// `sleepUnlocked` keeps the XPC listener responsive during the 0.4s FTST
    /// yield; `modeRetry`(12) x `modeRetrySleep`(0.05s) and the `Thread.sleep`
    /// durations are reverse-engineered and load-bearing. Changing any of this
    /// can break manual fan control on real hardware. (Refactor plan Phase 3
    /// deliberately leaves this section untouched.)
    ///
    /// Unlock then set forced mode. Do not fail the whole apply if mode
    /// readback stays at 0/3 — still write F{n}Tg afterwards. Sleeps without
    /// holding `lock` so status/XPC stay responsive.
    private func enterManual(_ i: Int) throws {
        guard let key = modeKeys[i] else { throw SMCError.missing(SMCKey.fanMode(i).rawValue) }
        if readMode(i) == 1 {
            holdFtst()
            return
        }
        _ = writeMode(key, 1)
        if readMode(i) == 1 {
            holdFtst()
            return
        }
        if let ftstKey {
            try smc.writeUInt8(ftstKey, 1, verify: false)
            ftstHeld = true
            sleepUnlocked(TC.ftstYield)
        }
        let attempts = ftstKey != nil ? TC.modeRetry : 8
        for _ in 0..<attempts {
            _ = writeMode(key, 1)
            if readMode(i) == 1 {
                holdFtst()
                return
            }
            sleepUnlocked(TC.modeRetrySleep)
        }
        holdFtst()
        let readback = readMode(i) ?? 255
        Logger.fan.warning("fan\(i) mode readback=\(readback); still writing target")
    }

    private func sleepUnlocked(_ t: TimeInterval) {
        lock.unlock()
        Thread.sleep(forTimeInterval: t)
        lock.lock()
    }

    private func readMode(_ i: Int) -> UInt8? {
        guard let key = modeKeys[i] else { return nil }
        return try? smc.readUInt8(key)
    }

    private func writeMode(_ key: String, _ v: UInt8) -> Bool {
        do { try smc.writeUInt8(key, v, verify: false); return true } catch { return false }
    }

    private func holdFtst() {
        guard let ftstKey, !ftstHeld else { return }
        try? smc.writeUInt8(ftstKey, 1, verify: false)
        ftstHeld = true
    }

    private func releaseFtst() {
        ftstHeld = false
        guard let ftstKey else { return }
        let cur = (try? smc.readUInt8(ftstKey)) ?? 0
        if cur == 1 { try? smc.writeUInt8(ftstKey, 0, verify: false) }
    }
}
