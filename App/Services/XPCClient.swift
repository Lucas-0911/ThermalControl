import Foundation
import os

final class XPCClient {
    private var connection: NSXPCConnection?

    private var proxy: ThermalHelperProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { err in
            Logger.xpc.error("proxy error: \(err.localizedDescription, privacy: .public)")
        } as? ThermalHelperProtocol
    }

    func connect() {
        invalidate()
        // System LaunchDaemon lives in the privileged bootstrap namespace.
        let c = NSXPCConnection(machServiceName: TC.machServiceName, options: [.privileged])
        c.remoteObjectInterface = ThermalXPC.makeInterface()
        c.interruptionHandler = { Logger.xpc.notice("connection interrupted") }
        c.invalidationHandler = { Logger.xpc.notice("connection invalidated") }
        c.resume()
        connection = c
    }

    func invalidate() {
        connection?.interruptionHandler = nil
        connection?.invalidationHandler = nil
        connection?.invalidate()
        connection = nil
    }

    func ping(_ done: @escaping (Bool) -> Void) {
        proxy?.ping("hb") { done($0) } ?? done(false)
    }

    func capabilities(_ done: @escaping (Capabilities?) -> Void) {
        proxy?.getCapabilities { done($0) } ?? done(nil)
    }

    func fanStatus(_ done: @escaping (FanStatus?) -> Void) {
        proxy?.getFanStatus { done($0) } ?? done(nil)
    }

    func batteryStatus(_ done: @escaping (BatteryStatus?) -> Void) {
        proxy?.getBatteryStatus { done($0) } ?? done(nil)
    }

    func setFanMode(_ mode: FanMode, _ done: @escaping (Bool, String?) -> Void) {
        proxy?.setFanMode(mode.rawValue) { done($0, $1) } ?? done(false, L10n.t("error.xpc"))
    }

    func setFanRPM(_ rpm: Int, index: Int, _ done: @escaping (Bool, String?) -> Void) {
        proxy?.setFanTargetRPM(rpm, fanIndex: index) { done($0, $1) } ?? done(false, L10n.t("error.xpc"))
    }

    func setChargeLimit(upper: Int, lower: Int, _ done: @escaping (Bool, String?) -> Void) {
        proxy?.setChargeLimit(upper, lower: lower) { done($0, $1) } ?? done(false, L10n.t("error.xpc"))
    }

    func setCharging(_ on: Bool, _ done: @escaping (Bool, String?) -> Void) {
        proxy?.setChargingEnabled(on) { done($0, $1) } ?? done(false, L10n.t("error.xpc"))
    }

    func setForceDischarge(_ on: Bool, _ done: @escaping (Bool, String?) -> Void) {
        proxy?.setForceDischarge(on) { done($0, $1) } ?? done(false, L10n.t("error.xpc"))
    }

    func restore(_ done: @escaping (Bool, String?) -> Void) {
        proxy?.restoreSystemControl { done($0, $1) } ?? done(false, L10n.t("error.xpc"))
    }

    func temps(_ done: @escaping ([TempReading]) -> Void) {
        proxy?.getThermalSnapshot { done($0) } ?? done([])
    }
}

/// Thin async wrappers (Phase 3a). The XPC protocol itself stays `@objc`
/// completion-based — `NSXPCInterface` requires it — but callers (the
/// view models) can now `await` instead of nesting completion handlers.
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

    func temps() async -> [TempReading] {
        await reply(or: []) { proxy, done in proxy.getThermalSnapshot(reply: done) }
    }

    private func reply<T>(or fallback: T, timeout: TimeInterval = 5,
                          _ request: (ThermalHelperProtocol, @escaping (T) -> Void) -> Void) async -> T {
        await withCheckedContinuation { continuation in
            let reply = XPCReply(continuation)
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                Logger.xpc.error("proxy error: \(error.localizedDescription, privacy: .public)")
                reply.resume(fallback)
            }) as? ThermalHelperProtocol else {
                reply.resume(fallback)
                return
            }
            request(proxy) { reply.resume($0) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                reply.resume(fallback)
            }
        }
    }
}

/// XPC may invoke its error handler without invoking the protocol reply. This
/// gate lets the reply or timeout win while resuming the continuation once.
final class XPCReply<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}
