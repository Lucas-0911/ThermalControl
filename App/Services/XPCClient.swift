import Foundation
import os

protocol ThermalHelperClient: AnyObject {
    func setFanMode(_ mode: FanMode) async -> (Bool, String?)
    func setFanRPM(_ rpm: Int, index: Int) async -> (Bool, String?)
    func setFanTargets(_ targets: [(index: Int, rpm: Int)]) async -> (Bool, String?)
    func fanStatus() async -> FanStatus?
    func batteryStatus() async -> BatteryStatus?
    func setChargeLimit(upper: Int, lower: Int) async -> (Bool, String?)
    func setCharging(_ on: Bool) async -> (Bool, String?)
    func setForceDischarge(_ on: Bool) async -> (Bool, String?)
}

@MainActor
protocol ThermalOrchestrationClient: ThermalHelperClient {
    var onConnectionLost: (() -> Void)? { get set }
    func connect()
    func invalidate()
    func ping() async -> Bool
    func capabilities() async -> Capabilities?
    func temps() async -> [TempReading]
    func restore() async -> (Bool, String?)
    func restore(components: Int) async -> RestoreResult
}

final class XPCClient: ThermalOrchestrationClient {
    private var connection: NSXPCConnection?
    private var pendingRequests: [UUID: () -> Void] = [:]
    var onConnectionLost: (() -> Void)?

    func connect() {
        invalidate()
        // System LaunchDaemon lives in the privileged bootstrap namespace.
        let c = NSXPCConnection(machServiceName: TC.machServiceName, options: [.privileged])
        c.remoteObjectInterface = ThermalXPC.makeInterface()
        c.interruptionHandler = { [weak self, weak c] in
            Logger.xpc.notice("connection interrupted")
            guard let c else { return }
            self?.connectionDidFail(c)
        }
        c.invalidationHandler = { [weak self, weak c] in
            Logger.xpc.notice("connection invalidated")
            guard let c else { return }
            self?.connectionDidFail(c)
        }
        c.resume()
        connection = c
    }

    func invalidate() {
        let pending = pendingRequests.values
        pendingRequests.removeAll()
        pending.forEach { $0() }
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        connection?.invalidate()
        connection = nil
    }

    private func connectionDidFail(_ failed: NSXPCConnection) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.connection === failed else { return }
            self.invalidate()
            self.onConnectionLost?()
        }
    }

}

/// Async wrappers around the Objective-C completion transport required by NSXPC.
extension XPCClient {
    func ping() async -> Bool {
        await reply(or: false) { proxy, done in proxy.ping("hb", reply: done) }
    }

    func capabilities() async -> Capabilities? {
        await reply(or: nil) { proxy, done in proxy.getCapabilities(reply: done) }
    }

    func fanStatus() async -> FanStatus? {
        await reply(or: nil) { proxy, done in proxy.getFanStatus(reply: done) }
    }

    func batteryStatus() async -> BatteryStatus? {
        await reply(or: nil) { proxy, done in proxy.getBatteryStatus(reply: done) }
    }

    func setFanMode(_ mode: FanMode) async -> (Bool, String?) {
        await reply(or: (false, L10n.t("error.xpc"))) { proxy, done in
            proxy.setFanMode(mode.rawValue) { done(($0, $1)) }
        }
    }

    func setFanRPM(_ rpm: Int, index: Int) async -> (Bool, String?) {
        await reply(or: (false, L10n.t("error.xpc"))) { proxy, done in
            proxy.setFanTargetRPM(rpm, fanIndex: index) { done(($0, $1)) }
        }
    }

    func setFanTargets(_ targets: [(index: Int, rpm: Int)]) async -> (Bool, String?) {
        let indexes = targets.map { NSNumber(value: $0.index) }
        let rpms = targets.map { NSNumber(value: $0.rpm) }
        return await reply(or: (false, L10n.t("error.xpc"))) { proxy, done in
            proxy.setFanTargets(indexes, rpms: rpms) { done(($0, $1)) }
        }
    }

    func setChargeLimit(upper: Int, lower: Int) async -> (Bool, String?) {
        await reply(or: (false, L10n.t("error.xpc"))) { proxy, done in
            proxy.setChargeLimit(upper, lower: lower) { done(($0, $1)) }
        }
    }

    func setCharging(_ on: Bool) async -> (Bool, String?) {
        await reply(or: (false, L10n.t("error.xpc"))) { proxy, done in
            proxy.setChargingEnabled(on) { done(($0, $1)) }
        }
    }

    func setForceDischarge(_ on: Bool) async -> (Bool, String?) {
        await reply(or: (false, L10n.t("error.xpc"))) { proxy, done in
            proxy.setForceDischarge(on) { done(($0, $1)) }
        }
    }

    func restore() async -> (Bool, String?) {
        await reply(or: (false, L10n.t("error.xpc"))) { proxy, done in
            proxy.restoreSystemControl { done(($0, $1)) }
        }
    }

    func restore(components: Int) async -> RestoreResult {
        let error = L10n.t("error.xpc")
        let fallback = RestoreResult(
            attempted: components,
            fanError: components & RestoreResult.fan == 0 ? nil : error,
            chargeError: components & RestoreResult.charge == 0 ? nil : error,
            dischargeError: components & RestoreResult.discharge == 0 ? nil : error
        )
        return await reply(or: fallback) { proxy, done in
            proxy.restoreComponents(components, reply: done)
        }
    }

    func temps() async -> [TempReading] {
        await reply(or: []) { proxy, done in proxy.getThermalSnapshot(reply: done) }
    }

    private func reply<T>(or fallback: T, timeout: TimeInterval = 5,
                          _ request: (ThermalHelperProtocol, @escaping (T) -> Void) -> Void) async -> T {
        let id = UUID()
        let reply = XPCReply<T>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                reply.install(continuation)
                guard !Task.isCancelled else { reply.resume(fallback); return }
                let timer = DispatchWorkItem { reply.resume(fallback) }
                reply.onFinish {
                    timer.cancel()
                    Task { @MainActor [weak self] in self?.pendingRequests[id] = nil }
                }
                pendingRequests[id] = { reply.resume(fallback) }
                guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                    Logger.xpc.error("proxy error: \(error.localizedDescription, privacy: .public)")
                    reply.resume(fallback)
                }) as? ThermalHelperProtocol else {
                    reply.resume(fallback)
                    return
                }
                guard !reply.isFinished else { return }
                request(proxy) { reply.resume($0) }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            }
        } onCancel: {
            reply.resume(fallback)
        }
    }
}

/// XPC may invoke its error handler without invoking the protocol reply. This
/// gate lets the reply or timeout win while resuming the continuation once.
final class XPCReply<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var result: T?
    private var finished = false
    private var cleanup: (() -> Void)?

    init() {}

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    var isFinished: Bool { lock.withLock { finished } }

    func install(_ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        if finished {
            let value = result!
            lock.unlock()
            continuation.resume(returning: value)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func onFinish(_ action: @escaping () -> Void) {
        lock.lock()
        if finished {
            lock.unlock()
            action()
        } else {
            cleanup = action
            lock.unlock()
        }
    }

    func resume(_ value: T) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        result = value
        let continuation = self.continuation
        let cleanup = self.cleanup
        self.continuation = nil
        self.cleanup = nil
        lock.unlock()
        cleanup?()
        continuation?.resume(returning: value)
    }
}
