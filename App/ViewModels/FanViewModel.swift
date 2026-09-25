import Foundation
import SwiftUI

/// Fan state + command sequencing, extracted from the `ThermalViewModel` god
/// object (Phase 4). Logic is behavior-identical to the original, with two
/// mechanical changes: XPC completion handlers → async wrappers, and
/// `UserDefaults` magic strings → `AppSettings`.
@MainActor
final class FanViewModel: ObservableObject {
    @Published var fanCount = 0
    @Published var fans: [FanChannel] = []
    @Published var desiredFanMode: FanMode = .system
    @Published var manualRPM: Int = 2500
    @Published var fanControl = false
    @Published var fanDrafts: [Int: Int] = [:]
    @Published var editingFan = false

    weak var host: (any ViewModelHost)?

    private let xpc: XPCClient
    private var fanApplyTask: Task<Void, Never>?
    private var applyingNamedFanMode = false
    private var fanSeq = 0

    init(xpc: XPCClient) {
        self.xpc = xpc
    }

    var showFan: Bool { fanCount > 0 || !fans.isEmpty }

    // MARK: - Settings

    func loadSettings() {
        let saved = AppSettings.manualRPM
        if saved > 0 { manualRPM = saved }
        // Per-fan Custom values survive relaunch; entering Custom no longer
        // picks up the previous mode's actual RPM when a saved draft exists.
        fanDrafts = AppSettings.fanDrafts
    }

    // MARK: - Inbound state

    func apply(capabilities cap: Capabilities) {
        fanCount = cap.fanCount
        fanControl = cap.fanControl
    }

    func apply(status st: FanStatus) {
        fans = st.fans
        fanCount = st.fans.count
        if !applyingNamedFanMode && !editingFan {
            let incoming = FanMode(rawValue: st.desiredMode) ?? .system
            // Keep Custom selected even if helper hasn't switched yet.
            if desiredFanMode != .manual {
                desiredFanMode = incoming
            }
        }
        if !editingFan && desiredFanMode == .manual {
            for f in st.fans {
                if fanDrafts[f.index] == nil {
                    fanDrafts[f.index] = Int((f.targetRPM > 0 ? f.targetRPM : f.actualRPM).rounded())
                }
            }
        }
        if let err = st.lastError, !err.isEmpty { host?.noteError(err) }
    }

    func applyLocalFans(_ localFans: [FanChannel]) {
        guard !localFans.isEmpty else { return }
        fans = localFans
        fanCount = localFans.count
    }

    // MARK: - Commands

    func cancelPendingCommands() {
        fanApplyTask?.cancel()
        fanApplyTask = nil
        fanSeq += 1
        applyingNamedFanMode = false
        editingFan = false
    }

    func setFanMode(_ mode: FanMode) {
        if mode == .manual {
            selectFanCustom()
            return
        }
        fanApplyTask?.cancel()
        editingFan = false
        fanSeq += 1
        let seq = fanSeq
        applyingNamedFanMode = true
        let prev = desiredFanMode
        desiredFanMode = mode
        Task { @MainActor [weak self] in
            guard let self else { return }
            let (ok, err) = await self.xpc.setFanMode(mode)
            guard self.fanSeq == seq else { return }
            self.applyingNamedFanMode = false
            if !ok {
                self.desiredFanMode = prev
                self.host?.surfaceError(err ?? L10n.t("error.cmd"))
            } else {
                self.host?.clearError()
            }
        }
    }

    func selectFanCustom() {
        fanApplyTask?.cancel()
        applyingNamedFanMode = false
        editingFan = false
        desiredFanMode = .manual
        // Seed only fans with NO saved draft (first use). Previously every
        // switch to Custom re-seeded from the previous mode's actual RPM,
        // discarding the user's configured values.
        var seeded = false
        for f in fans where fanDrafts[f.index] == nil {
            let seed = manualRPM > 0 ? Double(manualRPM) : (f.actualRPM > 0 ? f.actualRPM : sliderMin(for: f.index))
            fanDrafts[f.index] = Int(seed.rounded())
            seeded = true
        }
        if seeded { AppSettings.fanDrafts = fanDrafts }
        if manualRPM <= 0 { manualRPM = savedRPM(for: fans.first?.index ?? 0) }
        if fans.isEmpty && host?.isConnected != true {
            host?.surfaceError(L10n.t("error.xpc"))
            return
        }
        if !fans.isEmpty { setManualRPM() }
    }

    func setManualRPM() {
        fanApplyTask?.cancel()
        editingFan = false
        desiredFanMode = .manual
        if fans.count > 1 {
            for f in fans {
                setFanRPM(savedRPM(for: f.index), index: f.index)
            }
        } else {
            setFanRPM(manualRPM, index: -1)
        }
    }

    func scheduleFanApply(index: Int = -1) {
        desiredFanMode = .manual
        editingFan = true
        fanApplyTask?.cancel()
        fanApplyTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard let self, !Task.isCancelled else { return }
            self.editingFan = false
            if index < 0 {
                self.setFanRPM(self.manualRPM, index: -1)
            } else {
                self.setFanRPM(self.draftRPM(for: index), index: index)
            }
        }
    }

    func setFanRPM(_ rpm: Int, index: Int) {
        applyingNamedFanMode = false
        desiredFanMode = .manual
        guard host?.isConnected == true else {
            host?.surfaceError(L10n.t("error.xpc"))
            return
        }
        let lo = Int(sliderMin(for: index).rounded())
        let hi = Int(sliderMax(for: index).rounded())
        let clamped = min(max(rpm, lo), hi)
        if index < 0 {
            manualRPM = clamped
            AppSettings.manualRPM = clamped
            for f in fans { fanDrafts[f.index] = clamped }
        } else {
            fanDrafts[index] = clamped
        }
        AppSettings.fanDrafts = fanDrafts
        fanSeq += 1
        let seq = fanSeq
        Task { @MainActor [weak self] in
            guard let self else { return }
            let (ok, err) = await self.xpc.setFanRPM(clamped, index: index)
            guard self.fanSeq == seq else { return }
            self.editingFan = false
            if !ok {
                self.host?.surfaceError(err ?? L10n.t("error.cmd"))
            } else {
                self.host?.clearError()
            }
        }
    }

    // MARK: - Derived display values

    var sliderMin: Double { max(800, fans.first?.minRPM ?? 1000) }
    var sliderMax: Double { max(sliderMin + 100, fans.first?.maxRPM ?? 7000) }

    func sliderMin(for index: Int) -> Double {
        if let f = fans.first(where: { $0.index == index }) {
            return max(800, f.minRPM)
        }
        return sliderMin
    }

    func sliderMax(for index: Int) -> Double {
        let lo = sliderMin(for: index)
        if let f = fans.first(where: { $0.index == index }) {
            return max(lo + 100, f.maxRPM)
        }
        return sliderMax
    }

    func displayRPM(for fan: FanChannel) -> Double {
        switch desiredFanMode {
        case .quiet:
            return sliderMin(for: fan.index)
        case .max:
            return sliderMax(for: fan.index)
        case .manual:
            return Double(savedRPM(for: fan.index))
        case .system:
            return fan.actualRPM
        }
    }

    /// RPM shown in the number field for the current mode (not the saved custom, unless Custom is selected).
    var displayedModeRPM: Int {
        switch desiredFanMode {
        case .quiet: return Int(sliderMin.rounded())
        case .max: return Int(sliderMax.rounded())
        case .system: return Int((fans.first?.actualRPM ?? 0).rounded())
        case .manual: return manualRPM
        }
    }

    func displayedModeRPM(for index: Int) -> Int {
        if let f = fans.first(where: { $0.index == index }) {
            return Int(displayRPM(for: f).rounded())
        }
        return displayedModeRPM
    }

    /// User's last Custom RPM; never overwritten by Auto/Quiet/Max.
    func savedRPM(for index: Int) -> Int {
        if let v = fanDrafts[index] { return v }
        return manualRPM
    }

    var rpmFieldBinding: Binding<Int> {
        Binding(
            get: { self.desiredFanMode == .manual ? self.manualRPM : self.displayedModeRPM },
            set: { self.manualRPM = $0 }
        )
    }

    func rpmFieldBinding(for index: Int) -> Binding<Int> {
        Binding(
            get: {
                self.desiredFanMode == .manual
                    ? self.savedRPM(for: index)
                    : self.displayedModeRPM(for: index)
            },
            set: { self.fanDrafts[index] = $0 }
        )
    }

    func draftRPM(for index: Int) -> Int {
        savedRPM(for: index)
    }
}