import Foundation
import IOKit
import IOKit.ps
import os

enum SensorReader {
    private final class LocalSMC: @unchecked Sendable {
        let service = SMCService()
        private let lock = NSLock()
        private var ready = false

        func withService<T>(_ body: (any SMCProtocol) -> T) -> T? {
            lock.lock()
            defer { lock.unlock() }
            if !ready {
                do {
                    try service.open()
                    ready = true
                } catch {
                    Logger.smc.error("SensorReader open failed: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
            return body(service)
        }
    }

    private static let smc = LocalSMC()

    static func battery() -> (present: Bool, percent: Int, ac: Bool) {
        SensorReads.batteryIO()
    }

    static func fans() -> [FanChannel] {
        smc.withService { smc in
            let n = Int((try? smc.readUInt8(SMCKey.fanCount.rawValue)) ?? 0)
            guard n > 0 else { return [] }
            return (0..<n).map { i in
                let modeKey = smc.keyExists(SMCKey.fanMode(i).rawValue) ? SMCKey.fanMode(i).rawValue : SMCKey.fanModeLower(i).rawValue
                return SensorReads.fanChannel(index: i, modeKey: modeKey, smc: smc)
            }
        } ?? []
    }

    static func temps() -> [TempReading] {
        smc.withService { smc in
            TC.tempKeys.compactMap { k in
                guard let v = smc.readCelsius(k) else { return nil }
                return TempReading(key: k, celsius: v)
            }
        } ?? []
    }

    struct PowerInfo {
        var available = false
        var present = false
        var percent = 0
        var ac = false
        var batteryMA: Double = 0
        var voltageMV: Double = 0
        var adapterRatedW: Double = 0
        var systemInW: Double = 0
        var adapterName: String?
    }

    static func power() -> PowerInfo {
        var info = PowerInfo()
        let io = battery()
        info.present = io.present
        info.percent = io.percent
        info.ac = io.ac

        guard let props = smartBatteryProps() else { return info }
        info.available = true
        info.voltageMV = num(props["Voltage"])
        let instant = num(props["InstantAmperage"])
        info.batteryMA = instant != 0 ? instant : num(props["Amperage"])
        if bool(props["ExternalConnected"]) { info.ac = true }

        if let details = props["AdapterDetails"] as? [String: Any] {
            info.adapterRatedW = num(details["Watts"])
            info.adapterName = details["Name"] as? String
        }
        if info.adapterRatedW == 0, let raw = props["AppleRawAdapterDetails"] as? [Any], let first = raw.first as? [String: Any] {
            info.adapterRatedW = num(first["Watts"])
            if info.adapterName == nil { info.adapterName = first["Name"] as? String }
        }
        if let tel = props["PowerTelemetryData"] as? [String: Any] {
            let mw = num(tel["SystemPowerIn"])
            if mw > 0 { info.systemInW = mw / 1000 }
            if info.voltageMV == 0 { info.voltageMV = num(tel["SystemVoltageIn"]) }
        }
        return info
    }

    private static func smartBatteryProps() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    private static func num(_ any: Any?) -> Double {
        if let n = any as? NSNumber { return n.doubleValue }
        if let i = any as? Int { return Double(i) }
        if let i = any as? Int64 { return Double(i) }
        if let d = any as? Double { return d }
        return 0
    }

    private static func bool(_ any: Any?) -> Bool {
        if let b = any as? Bool { return b }
        if let n = any as? NSNumber { return n.boolValue }
        return false
    }
}
