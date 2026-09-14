import Foundation
import IOKit.ps

/// Shared sensor-snapshot readers used by BOTH processes (the app target
/// compiles `Shared/` and so does the helper daemon).
///
/// Before this existed, the IOKit battery loop and the per-fan SMC read were
/// copy-pasted between `SensorReader` (app) and `BatteryController`/
/// `FanController` (helper) with subtle drift risk.
enum SensorReads {
    /// Primary battery snapshot from Classic IOPS power sources.
    /// Fields must stay in sync with what `BatteryController.status()` and
    /// `SensorReader.battery()` consumed — present / percent / on-AC.
    static func batteryIO() -> (present: Bool, percent: Int, ac: Bool) {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else {
            return (false, 0, false)
        }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if (d[kIOPSTypeKey] as? String) != kIOPSInternalBatteryType { continue }
            let p = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let ac = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            return (true, p, ac)
        }
        return (false, 0, false)
    }

    /// One fan channel from the canonical `F{i}Ac/Tg/Mn/Mx/Md` reads.
    /// `modeKey` is caller-resolved (uppercase `F{i}Md` or lowercase `F{i}md`).
    static func fanChannel(index: Int, modeKey: String, smc: any SMCProtocol) -> FanChannel {
        FanChannel(
            index: index,
            actualRPM: (try? smc.readDouble(SMCKey.fanActual(index).rawValue)) ?? 0,
            targetRPM: (try? smc.readDouble(SMCKey.fanTarget(index).rawValue)) ?? 0,
            minRPM: (try? smc.readDouble(SMCKey.fanMin(index).rawValue)) ?? 0,
            maxRPM: (try? smc.readDouble(SMCKey.fanMax(index).rawValue)) ?? 0,
            modeRaw: Int((try? smc.readUInt8(modeKey)) ?? 3),
            modeKey: modeKey
        )
    }
}