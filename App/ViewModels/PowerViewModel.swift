import Foundation

struct PowerSample: Identifiable, Equatable {
    let time: Date
    let watts: Double
    var id: Date { time }
}

/// Power/usage history for the sparklines, extracted from the
/// `ThermalViewModel` god object (Phase 4). The orchestrator pushes samples
/// (after refreshing battery telemetry); this VM only owns the rolling
/// window + chart maxima.
@MainActor
final class PowerViewModel: ObservableObject {
    @Published var powerHistory: [PowerSample] = []
    @Published var usageHistory: [PowerSample] = []

    private var adapterCap: Double = 0

    func sample(inWatts: Double, usageWatts: Double, adapterCap: Double) {
        self.adapterCap = adapterCap
        let now = Date()
        let cutoff = now.addingTimeInterval(-TC.powerHistoryWindow)
        powerHistory.append(PowerSample(time: now, watts: max(0, inWatts)))
        powerHistory.removeAll { $0.time < cutoff }
        usageHistory.append(PowerSample(time: now, watts: usageWatts))
        usageHistory.removeAll { $0.time < cutoff }
    }

    var powerChartMax: Double { sparklineMax(powerHistory) }
    var usageChartMax: Double { sparklineMax(usageHistory) }

    private func sparklineMax(_ samples: [PowerSample]) -> Double {
        let peak = samples.map(\.watts).max() ?? 0
        let cap = max(adapterCap, 20)
        return max(10, min(cap, max(peak * 1.25, 8)))
    }
}