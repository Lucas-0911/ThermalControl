import Foundation
import os

final class FanController {
    private let smc: any SMCProtocol
    private let commandLock = NSLock()
    private let lock = NSLock()
    private var policyStore: FanPolicy = .system
    private(set) var lastError: String?
    private var ftstPresentStore = false
    private var modeKeys: [Int: String] = [:]
    private var fanCount = 0
    private var ftstKey: String?
    private var ftstHeld = false

    private let transactionLock: NSRecursiveLock
    private let monotonicNow: () -> TimeInterval
    private let scheduleAutomatic: Bool
    private let rampQueue = DispatchQueue(label: "com.thermalcontrol.fan-ramp", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var transitionID = 0
    private var ramping = false
    private var releasingToSystem = false
    private var forceWrote = false
    private var lastStep = 0.0
    private struct Target {
        let lower: Double
        let upper: Double
        let type: SMCType
        let goal: Double
        var position: Double
        var applied: Double
        var pendingSince: TimeInterval?
    }
    private var targets: [Int: Target] = [:]

    init(smc: any SMCProtocol, transactionLock: NSRecursiveLock = NSRecursiveLock(),
         monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         scheduleAutomatic: Bool = true) {
        self.smc = smc
        self.transactionLock = transactionLock
        self.monotonicNow = monotonicNow
        self.scheduleAutomatic = scheduleAutomatic
    }

    deinit { timer?.cancel() }

    var isRamping: Bool {
        lock.lock(); defer { lock.unlock() }
        return ramping
    }

    var policy: FanPolicy {
        lock.lock(); defer { lock.unlock() }
        return policyStore
    }

    var ftstPresent: Bool {
        lock.lock(); defer { lock.unlock() }
        return ftstPresentStore
    }

    var canControl: Bool {
        lock.lock(); defer { lock.unlock() }
        return canControlUnlocked
    }
    private var canControlUnlocked: Bool {
        fanCount > 0 && modeKeys.count == fanCount && (0..<fanCount).allSatisfy {
            smc.keyExists(SMCKey.fanTarget($0).rawValue)
        }
    }
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return fanCount
    }

    func probe() {
        transactionLock.lock(); defer { transactionLock.unlock() }
        commandLock.lock(); defer { commandLock.unlock() }
        lock.lock(); defer { lock.unlock() }
        cancelRamp()
        releasingToSystem = false
        targets.removeAll()
        fanCount = Int((try? smc.readUInt8(SMCKey.fanCount.rawValue)) ?? 0)
        if smc.keyExists(SMCKey.ftstLower.rawValue) {
            ftstKey = SMCKey.ftstLower.rawValue
        } else if smc.keyExists(SMCKey.ftst.rawValue) {
            ftstKey = SMCKey.ftst.rawValue
        } else {
            ftstKey = nil
        }
        ftstPresentStore = ftstKey != nil
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
        transactionLock.lock(); defer { transactionLock.unlock() }
        commandLock.lock(); defer { commandLock.unlock() }
        lock.lock(); defer { lock.unlock() }
        guard mode == .system || canControlUnlocked else { return (false, "Fan control is unsupported") }
        switch mode {
        case .system: return returnToAutoUnlocked()
        case .quiet: return commit(.quiet) { $0.minRPM.rounded() }
        case .max: return commit(.max) { $0.maxRPM.rounded() }
        case .manual: return (false, "Dùng Set RPM cho Manual")
        }
    }

    func setManual(rpm: Int, index: Int) -> (Bool, String?) {
        transactionLock.lock(); defer { transactionLock.unlock() }
        commandLock.lock(); defer { commandLock.unlock() }
        lock.lock(); defer { lock.unlock() }
        guard canControlUnlocked, index == -1 || (0..<fanCount).contains(index), rpm >= 0 else {
            return (false, "Invalid fan target")
        }
        var targets: [Int: Int] = [:]
        if case .manual(let existing) = policyStore {
            targets = existing
        }
        if index < 0 {
            for i in 0..<fanCount { targets[i] = rpm }
        } else {
            targets[index] = rpm
            for i in 0..<fanCount where targets[i] == nil {
                do {
                    let own = try self.targets[i]?.goal ?? readChecked(SMCKey.fanActual(i).rawValue) {
                        $0.isFinite && $0 >= 0 && $0 < Double(Int.max)
                    }
                    targets[i] = Int(own.rounded())
                } catch {
                    lastError = describe(error)
                    return (false, lastError)
                }
            }
        }
        let previousPolicy = policyStore
        policyStore = .manual(targets: targets)
        let result = force { Double(targets[$0.index] ?? rpm) }
        if !result.0 && !forceWrote { policyStore = previousPolicy }
        return result
    }

    func setManual(targets incoming: [Int: Int]) -> (Bool, String?) {
        transactionLock.lock(); defer { transactionLock.unlock() }
        commandLock.lock(); defer { commandLock.unlock() }
        lock.lock(); defer { lock.unlock() }
        guard canControlUnlocked, incoming.count == fanCount,
              incoming.keys.allSatisfy({ (0..<fanCount).contains($0) }),
              incoming.values.allSatisfy({ $0 >= 0 }) else {
            return (false, "Invalid fan target")
        }
        let previousPolicy = policyStore
        policyStore = .manual(targets: incoming)
        let result = force { Double(incoming[$0.index] ?? 0) }
        if !result.0 && !forceWrote { policyStore = previousPolicy }
        return result
    }

    @discardableResult
    func restoreSystem() -> (Bool, String?) {
        transactionLock.lock(); defer { transactionLock.unlock() }
        commandLock.lock(); defer { commandLock.unlock() }
        lock.lock(); defer { lock.unlock() }
        return restoreSystemUnlocked()
    }

    @discardableResult
    func apply() -> (Bool, String?) {
        transactionLock.lock(); defer { transactionLock.unlock() }
        commandLock.lock(); defer { commandLock.unlock() }
        lock.lock(); defer { lock.unlock() }
        return applyUnlocked()
    }

    private func statusUnlocked() -> FanStatus {
        var ch: [FanChannel] = []
        for i in 0..<fanCount {
            let key = modeKeys[i] ?? SMCKey.fanMode(i).rawValue
            let channel = SensorReads.fanChannel(index: i, modeKey: key, smc: smc)
            channel.goalRPM = targets[i]?.goal ?? -1
            ch.append(channel)
        }
        let mode = releasingToSystem ? FanMode.system.rawValue : policyStore.modeRaw
        return FanStatus(fans: ch, desiredMode: mode, ftstPresent: ftstPresentStore, lastError: lastError,
                         ramping: ramping, transitionID: transitionID)
    }

    private func restoreSystemUnlocked() -> (Bool, String?) {
        releasingToSystem = false
        cancelRamp()
        targets.removeAll()
        var errors: [String] = []
        var pending: [Int: String] = [:]
        for i in 0..<fanCount {
            guard let key = modeKeys[i] else { continue }
            do {
                try smc.writeUInt8(key, 0, verify: false)
                pending[i] = key
            } catch { errors.append("fan\(i): \((error as? SMCError)?.description ?? error.localizedDescription)") }
        }
        releaseFtst()
        // Auto readback may lag the write; bounded polling never rewrites the command.
        for attempt in 0...5 {
            for i in pending.keys.sorted() {
                let key = pending[i]!
                do {
                    let actual = try smc.readUInt8(key)
                    if actual == 0 { pending.removeValue(forKey: i) }
                    else if attempt == 5 {
                        errors.append("fan\(i): Verify fail \(key): expected=0 actual=\(actual)")
                    }
                } catch {
                    if attempt == 5 {
                        errors.append("fan\(i): \((error as? SMCError)?.description ?? error.localizedDescription)")
                    }
                }
            }
            if pending.isEmpty || attempt == 5 { break }
            sleepUnlocked(0.05)
        }
        // Keep the safe policy even after a partial failure; watchdog must not reapply an override.
        policyStore = .system
        lastError = errors.isEmpty ? nil : errors.joined(separator: "; ")
        return (errors.isEmpty, lastError)
    }

    private func applyUnlocked() -> (Bool, String?) {
        if policyStore == .system { return restoreSystemUnlocked() }
        // ponytail: watchdog reasserts the last step; only explicit commands start a transition.
        guard targets.count == fanCount, !targets.isEmpty else { return (false, "Fan transition was invalidated") }
        do {
            let now = monotonicNow()
            guard now.isFinite else { throw SMCError.verify("Fan clock") }
            for i in targets.keys.sorted() where targets[i]!.pendingSince == nil {
                try writeTarget(i, targets[i]!.applied, now: now)
            }
            updateRampState()
            return (true, nil)
        } catch { return holdFans(error) }
    }

    private func commit(_ policy: FanPolicy, _ rpm: (FanChannel) -> Double) -> (Bool, String?) {
        let previous = policyStore
        let result = force(rpm: rpm, releaseWhenReached: false)
        if result.0 || forceWrote { policyStore = policy }
        else { policyStore = previous }
        return result
    }

    /// Reads the RPM macOS publishes in `F{n}Tg` after a mode-0 write, puts the
    /// previous target back, then ramps to that sample before releasing Auto.
    private func returnToAutoUnlocked() -> (Bool, String?) {
        if policyStore == .system && !ramping && targets.isEmpty {
            return restoreSystemUnlocked()
        }
        var held: [Int: Double] = [:]
        for i in 0..<fanCount {
            if let applied = targets[i]?.applied {
                held[i] = applied
            } else {
                do {
                    held[i] = try readChecked(SMCKey.fanActual(i).rawValue) { $0.isFinite && $0 >= 0 }
                } catch {
                    lastError = describe(error)
                    return (false, lastError)
                }
            }
        }
        for i in held.keys {
            guard let target = targets[i] else { continue }
            targets[i] = Target(lower: target.lower, upper: target.upper, type: target.type,
                                goal: held[i]!, position: held[i]!, applied: held[i]!, pendingSince: nil)
        }
        cancelRamp()
        releaseFtst()
        for i in 0..<fanCount {
            guard let key = modeKeys[i] else { continue }
            _ = writeMode(key, 0)
        }
        var sampled: [Int: Double] = [:]
        do {
            for i in 0..<fanCount {
                sampled[i] = try readChecked(SMCKey.fanTarget(i).rawValue) { $0.isFinite && $0 >= 0 }
            }
            try reassert(held)
        } catch {
            do { try reassert(held) } catch {
                lastError = describe(error)
                return (false, lastError)
            }
            lastError = describe(error)
            return (false, lastError)
        }
        return force(rpm: { sampled[$0.index] ?? $0.actualRPM }, releaseWhenReached: true)
    }

    private func force(rpm: (FanChannel) -> Double, releaseWhenReached: Bool = false) -> (Bool, String?) {
        let previous = targets
        forceWrote = false
        releasingToSystem = false
        cancelRamp()
        targets.removeAll()
        do {
            for i in 0..<fanCount {
                let lo = try readChecked(SMCKey.fanMin(i).rawValue) { $0.isFinite && $0 > 0 }
                let hi = try readChecked(SMCKey.fanMax(i).rawValue) { $0.isFinite && $0 > lo }
                let actual: Double
                if let applied = previous[i]?.applied, applied.isFinite, applied >= 0 {
                    actual = applied
                } else {
                    actual = try readChecked(SMCKey.fanActual(i).rawValue) { $0.isFinite && $0 >= 0 }
                }
                let key = SMCKey.fanTarget(i).rawValue
                let meta = try smc.info(key)
                let lower: Double
                let upper: Double
                switch meta.type {
                case .flt where meta.dataSize == 4:
                    guard hi <= Double(Float.greatestFiniteMagnitude) else { throw SMCError.type(key) }
                    let a = Float(lo), b = Float(hi)
                    lower = Double(Double(a) < lo ? a.nextUp : a)
                    upper = Double(Double(b) > hi ? b.nextDown : b)
                case .fpe2 where meta.dataSize == 2:
                    lower = (lo * 4).rounded(.up) / 4
                    upper = min(16_383.75, (hi * 4).rounded(.down) / 4)
                case .ui8 where meta.dataSize == 1:
                    lower = lo.rounded(.up)
                    upper = min(255, hi.rounded(.down))
                default: throw SMCError.type(key)
                }
                guard lower.isFinite, upper.isFinite, lower <= upper else { throw SMCError.type(key) }
                let channel = FanChannel(index: i, actualRPM: actual, targetRPM: actual,
                                         minRPM: lo, maxRPM: hi, modeRaw: 1, modeKey: modeKeys[i] ?? "")
                let requested = rpm(channel)
                guard requested.isFinite else { throw SMCError.verify(key) }
                let goal = encoded(min(max(requested, lower), upper), type: meta.type)
                // ponytail: firmware may stop Auto fans; start at its minimum, never ramp below that floor.
                let start = encoded(min(max(actual, lower), upper), type: meta.type)
                if previous[i]?.pendingSince != nil, start != actual { throw SMCError.verify(key) }
                targets[i] = Target(lower: lower, upper: upper, type: meta.type, goal: goal,
                                    position: start, applied: start, pendingSince: previous[i]?.pendingSince)
            }
            for i in targets.keys.sorted() {
                if previous[i] == nil {
                    forceWrote = true
                    try enterManual(i)
                }
                let now = monotonicNow()
                guard now.isFinite else { throw SMCError.verify("Fan clock") }
                if previous[i] == nil || previous[i]!.applied != targets[i]!.applied {
                    try writeTarget(i, targets[i]!.applied, now: now)
                }
            }
            lastStep = monotonicNow()
            guard lastStep.isFinite else { throw SMCError.verify("Fan clock") }
            lastError = nil
            releasingToSystem = releaseWhenReached
            updateRampState()
            if releaseWhenReached && !ramping { return restoreSystemUnlocked() }
            return (true, nil)
        } catch {
            if !forceWrote {
                targets = previous
                releasingToSystem = false
                lastError = describe(error)
                if previous.values.contains(where: { $0.pendingSince != nil || $0.applied != $0.goal }) {
                    updateRampState()
                }
                return (false, lastError)
            }
            return holdFans(error)
        }
    }

    /// Same step for the timer and deterministic fake-SMC tests. Never catches up after a stalled tick.
    func advanceRamp(transitionID expected: Int? = nil) {
        transactionLock.lock(); defer { transactionLock.unlock() }
        commandLock.lock(); defer { commandLock.unlock() }
        lock.lock(); defer { lock.unlock() }
        guard expected == nil || expected == transitionID, ramping else { return }
        do {
            let now = monotonicNow()
            guard now.isFinite else { throw SMCError.verify("Fan clock") }
            let step = 250 * min(max(now - lastStep, 0), 0.25)
            lastStep = now
            for i in targets.keys.sorted() {
                var target = targets[i]!
                if let since = target.pendingSince {
                    let key = SMCKey.fanTarget(i).rawValue
                    let actual = try smc.readDouble(key)
                    if actual == target.applied {
                        target.pendingSince = nil
                    } else if now - since >= 1 {
                        let meta = try smc.info(key)
                        throw NSError(domain: "ThermalControl.FanReadback", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey:
                                        "Verify fail \(key): expected=\(target.applied) actual=\(actual) type=\(meta.typeFourCC) size=\(meta.dataSize) timeout=1.0s"])
                    }
                    // A late readback must not freeze the glide. The next point is still written.
                }
                target.position += min(abs(target.goal - target.position), step) * (target.goal >= target.position ? 1 : -1)
                let next = encoded(min(max(target.position, target.lower), target.upper), type: target.type)
                targets[i] = target
                if next != target.applied { try writeTarget(i, next, now: now) }
            }
            updateRampState()
            if releasingToSystem && !ramping { _ = restoreSystemUnlocked() }
        } catch { _ = holdFans(error) }
    }

    private func encoded(_ value: Double, type: SMCType) -> Double {
        switch type {
        case .flt: return Double(Float(value))
        case .fpe2: return (value * 4).rounded() / 4
        case .ui8: return value.rounded()
        default: return value // Unsupported encodings are rejected before any write.
        }
    }

    private func writeTarget(_ index: Int, _ value: Double, now: TimeInterval) throws {
        try smc.writeDouble(SMCKey.fanTarget(index).rawValue, value, verify: false)
        forceWrote = true
        targets[index]!.applied = value
        if targets[index]!.pendingSince == nil {
            targets[index]!.pendingSince = now
        }
    }

    /// One bad min/max/actual sample is not a mode change. The message names the key that failed.
    private func readChecked(_ key: String, accept: (Double) -> Bool) throws -> Double {
        var last = "Verify fail \(key)"
        for attempt in 0..<5 {
            do {
                let value = try smc.readDouble(key)
                if accept(value) { return value }
                last = "Verify fail \(key): actual=\(value)"
            } catch {
                last = "Verify fail \(key)"
            }
            if attempt < 4 { sleepUnlocked(0.05) }
        }
        throw NSError(domain: "ThermalControl.FanReadback", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: last])
    }

    private func reassert(_ held: [Int: Double]) throws {
        for i in held.keys.sorted() {
            guard let modeKey = modeKeys[i] else { throw SMCError.missing(SMCKey.fanMode(i).rawValue) }
            let targetKey = SMCKey.fanTarget(i).rawValue
            if readMode(i) != 1 { _ = writeMode(modeKey, 1) }
            if readMode(i) != 1 {
                try smc.writeDouble(targetKey, held[i]!, verify: false)
                try enterManual(i)
            } else {
                holdFtst()
            }
            try smc.writeDouble(targetKey, held[i]!, verify: false)
            if var target = targets[i] {
                target.applied = held[i]!
                target.pendingSince = nil
                targets[i] = target
            }
        }
    }

    private func describe(_ error: Error) -> String {
        (error as? SMCError)?.description ?? error.localizedDescription
    }

    /// Stop the ramp at the last applied RPM. Do not hand the fans back to Auto.
    private func holdFans(_ error: Error) -> (Bool, String?) {
        releasingToSystem = false
        for index in targets.keys {
            let target = targets[index]!
            targets[index] = Target(lower: target.lower, upper: target.upper, type: target.type,
                                    goal: target.applied, position: target.applied,
                                    applied: target.applied, pendingSince: nil)
        }
        cancelRamp()
        lastError = describe(error)
        return (false, lastError)
    }

    private func updateRampState() {
        ramping = targets.values.contains { $0.pendingSince != nil || $0.applied != $0.goal }
        if !ramping { timer?.cancel(); timer = nil }
        else if timer == nil, scheduleAutomatic {
            let id = transitionID
            let source = DispatchSource.makeTimerSource(queue: rampQueue)
            source.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
            source.setEventHandler { [weak self] in self?.advanceRamp(transitionID: id) }
            timer = source
            source.resume()
        }
    }

    private func cancelRamp() {
        transitionID &+= 1
        ramping = false
        timer?.cancel()
        timer = nil
    }

    // MARK: - DO NOT MODIFY (hardware timing)

    /// FTST unlock + forced-mode sequence. The unlock-before-sleep in
    /// `sleepUnlocked` keeps the XPC listener responsive during the 0.4s FTST
    /// yield; `modeRetry`(12) x `modeRetrySleep`(0.05s) and the `Thread.sleep`
    /// durations are reverse-engineered and load-bearing. Changing any of this
    /// can break manual fan control on real hardware.
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
