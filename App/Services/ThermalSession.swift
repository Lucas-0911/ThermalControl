import AppKit

/// Owns polling and workspace observers independently of SwiftUI view identity.
@MainActor
final class ThermalSession {
    private var heartbeat: Timer?
    private var telemetry: Timer?
    private var power: Timer?
    private var observers: [NSObjectProtocol] = []
    private(set) var started = false
    private(set) var sleeping = false
    private(set) var menuVisible = false
    private(set) var dashboardVisible = false
#if DEBUG
    var activeTimerCountForTesting: Int { [heartbeat, telemetry, power].compactMap { $0 }.filter(\.isValid).count }
#endif
    var onRefresh: (() -> Void)?
    var onHeartbeat: (() -> Void)?
    var onPowerSample: (() -> Void)?
    var onSleep: (() -> Void)?
    var onWake: (() -> Void)?

    func start() {
        guard !started else { return }
        started = true
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onWake?() }
            }
        ]
        resume()
    }

    func stop() {
        suspend()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        started = false
    }

    func pause() {
        sleeping = true
        suspend()
    }

    func sleep() {
        pause()
        onSleep?()
    }

    func resume() {
        sleeping = false
        guard started else { return }
        heartbeat?.invalidate()
        heartbeat = timer(interval: TC.heartbeatInterval) { [weak self] in self?.onHeartbeat?() }
        scheduleTelemetry()
    }

    func setVisibility(menu: Bool? = nil, dashboard: Bool? = nil) {
        let changed = (menu != nil && menu != menuVisible) || (dashboard != nil && dashboard != dashboardVisible)
        guard changed else { return }
        if let menu { menuVisible = menu }
        if let dashboard { dashboardVisible = dashboard }
        guard started, !sleeping else { return }
        scheduleTelemetry()
        if menuVisible || dashboardVisible { onRefresh?() }
    }

    private func scheduleTelemetry() {
        telemetry?.invalidate()
        let interval = dashboardVisible ? TC.dashboardPollInterval : menuVisible ? TC.menuPollInterval : TC.backgroundPollInterval
        telemetry = timer(interval: interval) { [weak self] in self?.onRefresh?() }
        power?.invalidate()
        power = nil
        if dashboardVisible {
            onPowerSample?()
            power = timer(interval: TC.powerSampleInterval) { [weak self] in self?.onPowerSample?() }
        }
    }

    private func timer(interval: TimeInterval, action: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        timer.tolerance = min(interval * 0.1, 0.5)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func suspend() {
        heartbeat?.invalidate()
        telemetry?.invalidate()
        power?.invalidate()
        heartbeat = nil
        telemetry = nil
        power = nil
    }
}
