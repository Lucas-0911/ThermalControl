import Foundation
import SwiftUI

/// Numeric edits are drafts. Only an explicit Apply writes fixed RPM targets.
@MainActor
final class FanViewModel: ObservableObject {
    @Published var fanCount = 0
    @Published var fans: [FanChannel] = []
    @Published var desiredFanMode: FanMode = .system
    @Published var manualRPM = 2500
    @Published var fanControl = false
    @Published var fanDrafts: [Int: Int] = [:]
    @Published var editingFan = false
    @Published private(set) var isApplying = false
    @Published private(set) var isRamping = false
    @Published private(set) var errorMessage: String?

    weak var host: (any ViewModelHost)?
    private let xpc: any ThermalHelperClient
    private enum Command {
        case mode(FanMode)
        case targets([(index: Int, rpm: Int)])
    }
    private var commands: [Command] = []
    private var commandTask: Task<Void, Never>?
    private var generation = 0
    private var confirmedMode: FanMode = .system
    private var confirmedTargets: [Int: Int] = [:]
    private var overrideMayBeActive = false
    private var latestTransitionID = -1
    private var completedTransitionID = -1
    private var pendingConfirmation: (transitionID: Int, command: Command)?

    var hasTransientOverride: Bool { desiredFanMode != .system || isApplying || isRamping || overrideMayBeActive }
    private var retainFanEditor = false

    init(xpc: any ThermalHelperClient) { self.xpc = xpc }

    var showFan: Bool { fanCount > 0 || !fans.isEmpty }
    var hasValidFanLimits: Bool { !fans.isEmpty && fans.allSatisfy { $0.maxRPM > $0.minRPM } }

    private func sanitizedFans(_ channels: [FanChannel]) -> [FanChannel] {
        func valid(_ value: Double) -> Bool {
            value.isFinite && value >= 0 && value <= Double(Int32.max)
        }
        return channels.map {
            let validLimits = valid($0.minRPM) && valid($0.maxRPM) && $0.maxRPM > $0.minRPM
            return FanChannel(index: $0.index, actualRPM: valid($0.actualRPM) ? $0.actualRPM : 0,
                              targetRPM: valid($0.targetRPM) ? $0.targetRPM : 0,
                              minRPM: validLimits ? $0.minRPM : 0, maxRPM: validLimits ? $0.maxRPM : 0,
                              modeRaw: $0.modeRaw, modeKey: $0.modeKey,
                              goalRPM: valid($0.goalRPM) ? $0.goalRPM : -1)
        }
    }

    func loadSettings() {
        let saved = AppSettings.manualRPM
        if saved > 0 { manualRPM = saved }
        fanDrafts = AppSettings.fanDrafts
    }

    func apply(capabilities cap: Capabilities) {
        fanCount = cap.fanCount
        fanControl = cap.fanControl
    }

    func apply(status st: FanStatus) {
        guard st.transitionID >= latestTransitionID,
              !(st.transitionID == completedTransitionID && st.ramping) else { return }
        latestTransitionID = st.transitionID
        if !st.ramping { completedTransitionID = st.transitionID }
        isRamping = st.ramping
        fans = sanitizedFans(st.fans)
        fanCount = st.fans.count
        confirmedMode = FanMode(rawValue: st.desiredMode) ?? .system
        if !isApplying && st.lastError?.isEmpty != false {
            overrideMayBeActive = confirmedMode != .system
        }
        for fan in fans {
            if !st.ramping, fan.targetRPM > 0 {
                confirmedTargets[fan.index] = Int(fan.targetRPM.rounded())
            }
            if fanDrafts[fan.index] == nil {
                fanDrafts[fan.index] = goalRPM(for: fan.index).map { Int($0.rounded()) }
                    ?? confirmedTargets[fan.index] ?? manualRPM
            }
        }
        if !isApplying { desiredFanMode = confirmedMode }
        if let pending = pendingConfirmation {
            if st.transitionID > pending.transitionID {
                pendingConfirmation = nil
            } else if st.transitionID == pending.transitionID, !st.ramping {
                pendingConfirmation = nil
                if matches(pending.command, status: st, terminal: true) {
                    if case .targets(let targets) = pending.command { persistTargets(targets) }
                } else {
                    errorMessage = st.lastError ?? L10n.t("error.readback")
                }
            }
        }
        if let error = st.lastError, !error.isEmpty, errorMessage == nil { errorMessage = error }
    }

    func applyLocalFans(_ localFans: [FanChannel]) {
        guard !localFans.isEmpty else { return }
        fans = sanitizedFans(localFans)
        fanCount = localFans.count
    }

    func cancelPendingCommands() {
        generation += 1
        pendingConfirmation = nil
        isRamping = false
        latestTransitionID = -1
        completedTransitionID = -1
        commands.removeAll()
        commandTask?.cancel()
        commandTask = nil
        isApplying = false
        desiredFanMode = confirmedMode
        // ponytail: preserve local drafts, but never replay a cancelled or disconnected write.
    }

    func setFanMode(_ mode: FanMode) {
        if mode == .manual { selectFanCustom(); return }
        guard host?.isConnected == true, fanControl else { return }
        errorMessage = nil
        pendingConfirmation = nil
        desiredFanMode = mode
        commands = [.mode(mode)]
        drainCommands()
    }

    func selectFanCustom() {
        editingFan = true
        for fan in fans where fanDrafts[fan.index] == nil {
            fanDrafts[fan.index] = confirmedTargets[fan.index] ?? manualRPM
        }
    }

    func cancelFanEdits() {
        retainFanEditor = false
        let rpm = confirmedTargets[primaryIndex] ?? manualRPM
        for target in balancedTargets(primaryRPM: rpm) { fanDrafts[target.index] = target.rpm }
        manualRPM = savedRPM(for: primaryIndex)
        editingFan = false
    }

    /// Menu bar Custom applies the saved fan-1 RPM, or 50% of its min–max range.
    func applySavedCustom() {
        retainFanEditor = false
        editingFan = false
        storeDrafts(balancedTargets(primaryRPM: savedCustomRPM()))
        sendManualTargets()
    }

    func savedCustomRPM() -> Int {
        if AppSettings.manualRPM > 0 { return AppSettings.manualRPM }
        if let saved = AppSettings.fanDrafts[primaryIndex], saved > 0 { return saved }
        return midpointRPM(for: primaryIndex)
    }

    func midpointRPM(for index: Int) -> Int {
        let lo = sliderMin(for: index)
        let hi = sliderMax(for: index)
        return clampedRPM(Int((lo + (hi - lo) * 0.5).rounded()), index: index)
    }

    func setManualRPM() {
        retainFanEditor = false
        storeDrafts(balancedTargets(primaryRPM: savedRPM(for: primaryIndex)))
        sendManualTargets()
    }

    private func sendManualTargets() {
        guard host?.isConnected == true, fanControl, hasValidFanLimits else { return }
        let targets = balancedTargets(primaryRPM: savedRPM(for: primaryIndex))
        storeDrafts(targets)
        errorMessage = nil
        pendingConfirmation = nil
        desiredFanMode = .manual
        commands = [.targets(targets)]
        drainCommands()
    }

    func setFanRPM(_ rpm: Int, index: Int) {
        guard index == -1 || fans.contains(where: { $0.index == index }) else { return }
        if index < 0 {
            manualRPM = clampedRPM(rpm, index: index)
            for fan in fans { fanDrafts[fan.index] = clampedRPM(rpm, index: fan.index) }
        } else {
            fanDrafts[index] = clampedRPM(rpm, index: index)
        }
        setManualRPM()
    }

    private func drainCommands() {
        guard commandTask == nil else { return }
        let current = generation
        isApplying = true
        commandTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.generation == current else { return }
            while !self.commands.isEmpty {
                let command = self.commands.removeFirst()
                var result: (Bool, String?) = (true, nil)
                // A timed-out write may still reach hardware; keep cleanup required until readback proves Auto.
                self.overrideMayBeActive = true
                switch command {
                case .mode(let mode):
                    result = await self.xpc.setFanMode(mode)
                case .targets(let targets):
                    guard !Task.isCancelled, self.generation == current else { return }
                    result = await self.xpc.setFanTargets(targets)
                }
                guard self.generation == current, !Task.isCancelled else { return }
                if !self.commands.isEmpty { continue }
                let status = await self.xpc.fanStatus()
                guard self.generation == current, !Task.isCancelled else { return }
                if !self.commands.isEmpty { continue }
                if let status, status.transitionID >= self.latestTransitionID {
                    self.apply(status: status)
                    let confirmed = self.matches(command, status: status)
                    if status.desiredMode == FanMode.system.rawValue, !status.ramping, status.lastError?.isEmpty != false {
                        self.overrideMayBeActive = false
                    }
                    if !result.0 || !confirmed {
                        if case .targets(let targets) = command, targets.count > 1 {
                            let count = targets.filter { self.matchesTarget($0, status: status) }.count
                            if count > 0, count < targets.count {
                                self.errorMessage = L10n.t("fan.partial", count, targets.count)
                            } else {
                                self.errorMessage = result.1 ?? L10n.t("error.readback")
                            }
                        } else {
                            self.errorMessage = result.1 ?? L10n.t("error.readback")
                        }
                    } else {
                        self.errorMessage = nil
                        if status.ramping {
                            self.pendingConfirmation = (status.transitionID, command)
                        } else if case .targets(let targets) = command,
                                  self.matches(command, status: status, terminal: true) {
                            self.persistTargets(targets)
                        }
                    }
                } else if status == nil {
                    self.errorMessage = result.1 ?? L10n.t("error.readback")
                }
            }
            self.desiredFanMode = self.confirmedMode
            self.isApplying = false
            self.commandTask = nil
        }
    }

    private func persistTargets(_ targets: [(index: Int, rpm: Int)]) {
        var saved = AppSettings.fanDrafts
        for target in targets { saved[target.index] = target.rpm }
        AppSettings.fanDrafts = saved
        if let first = targets.first {
            manualRPM = first.rpm
            AppSettings.manualRPM = first.rpm
        }
        if !retainFanEditor, targets.allSatisfy({ savedRPM(for: $0.index) == $0.rpm }) { editingFan = false }
    }

    private func matchesTarget(_ target: (index: Int, rpm: Int), status: FanStatus, terminal: Bool = false) -> Bool {
        status.desiredMode == FanMode.manual.rawValue && status.fans.contains {
            guard $0.index == target.index else { return false }
            let accepted = $0.goalRPM >= 0 ? $0.goalRPM : $0.targetRPM
            let readback = terminal || !status.ramping ? $0.targetRPM : accepted
            return accepted.isFinite && abs(accepted - Double(target.rpm)) <= 1
                && readback.isFinite && abs(readback - Double(target.rpm)) <= 1
        }
    }

    private func matches(_ command: Command, status: FanStatus, terminal: Bool = false) -> Bool {
        guard status.lastError?.isEmpty != false, !terminal || !status.ramping else { return false }
        switch command {
        case .targets(let targets):
            return targets.allSatisfy { matchesTarget($0, status: status, terminal: terminal) }
        case .mode(let mode):
            guard status.desiredMode == mode.rawValue, !status.fans.isEmpty else { return false }
            if mode == .system {
                if status.ramping && !terminal {
                    return status.fans.allSatisfy { $0.goalRPM.isFinite && $0.goalRPM >= 0 }
                }
                return !status.ramping
            }
            return status.fans.allSatisfy {
                let goal = $0.goalRPM >= 0 ? $0.goalRPM : (mode == .quiet ? $0.minRPM : $0.maxRPM).rounded()
                guard goal.isFinite else { return false }
                if status.ramping && !terminal { return $0.goalRPM.isFinite && $0.goalRPM >= 0 }
                return $0.targetRPM.isFinite && abs($0.targetRPM - goal) <= 1
            }
        }
    }

    func goalRPM(for index: Int) -> Double? {
        guard let fan = fans.first(where: { $0.index == index }), fan.goalRPM >= 0 else { return nil }
        return fan.goalRPM
    }

    private func clampedRPM(_ rpm: Int, index: Int) -> Int {
        min(max(rpm, Int(sliderMin(for: index))), Int(sliderMax(for: index)))
    }

    var sliderMin: Double { max(0, fans.first?.minRPM ?? 1000) }
    var sliderMax: Double { max(sliderMin + 1, fans.first?.maxRPM ?? 7000) }

    func sliderMin(for index: Int) -> Double {
        fans.first(where: { $0.index == index }).map { max(0, $0.minRPM) } ?? sliderMin
    }

    func sliderMax(for index: Int) -> Double {
        fans.first(where: { $0.index == index }).map { max(sliderMin(for: index) + 1, $0.maxRPM) } ?? sliderMax
    }

    func displayRPM(for fan: FanChannel) -> Double { fan.actualRPM.isFinite ? fan.actualRPM : 0 }
    func savedRPM(for index: Int) -> Int { fanDrafts[index] ?? manualRPM }
    func draftRPM(for index: Int) -> Int { savedRPM(for: index) }
    var primaryIndex: Int { fans.map(\.index).min() ?? 0 }

    /// Fan 1 takes `primaryRPM`. Each later fan takes the same position in its own min–max range.
    func balancedTargets(primaryRPM: Int) -> [(index: Int, rpm: Int)] {
        let ordered = fans.sorted { $0.index < $1.index }
        guard let primary = ordered.first else { return [] }
        let rpm = clampedRPM(primaryRPM, index: primary.index)
        let span = sliderMax(for: primary.index) - sliderMin(for: primary.index)
        let fraction = span > 0 ? (Double(rpm) - sliderMin(for: primary.index)) / span : 0
        return ordered.map { fan in
            if fan.index == primary.index { return (fan.index, rpm) }
            let lo = sliderMin(for: fan.index)
            let hi = sliderMax(for: fan.index)
            let value = Int((lo + fraction * (hi - lo)).rounded())
            return (fan.index, clampedRPM(value, index: fan.index))
        }
    }

    func balancedRPM(for index: Int) -> Int {
        balancedTargets(primaryRPM: savedRPM(for: primaryIndex)).first { $0.index == index }?.rpm ?? savedRPM(for: index)
    }

    func rpmFieldBinding(for index: Int) -> Binding<Int> {
        Binding(get: { self.balancedRPM(for: index) }, set: { newValue in
            let targets = self.balancedTargets(primaryRPM: newValue)
            if targets.isEmpty {
                self.fanDrafts[index] = newValue
                self.manualRPM = newValue
            } else {
                self.storeDrafts(targets)
            }
            self.editingFan = true
        })
    }

    private func storeDrafts(_ targets: [(index: Int, rpm: Int)]) {
        for target in targets { fanDrafts[target.index] = target.rpm }
        if let primary = targets.first(where: { $0.index == primaryIndex }) ?? targets.first {
            manualRPM = primary.rpm
        }
    }
}
