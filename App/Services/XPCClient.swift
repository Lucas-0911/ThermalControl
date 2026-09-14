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
        connection?.invalidate()
        // System LaunchDaemon lives in the privileged bootstrap namespace.
        let c = NSXPCConnection(machServiceName: TC.machServiceName, options: [.privileged])
        c.remoteObjectInterface = ThermalXPC.makeInterface()
        c.interruptionHandler = { Logger.xpc.notice("connection interrupted") }
        c.invalidationHandler = { Logger.xpc.notice("connection invalidated") }
        c.resume()
        connection = c
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
