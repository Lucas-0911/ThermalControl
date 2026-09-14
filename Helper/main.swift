import Foundation
import os

// Wiring (was inside the old `HelperDelegate.init` god object — Phase 3c).
let smc = SMCService()
let fan = FanController(smc: smc)
let battery = BatteryController(smc: smc)
let watchdog = SafetyWatchdog(smc: smc, fan: fan, battery: battery)
let service = HelperXPCService(smc: smc, fan: fan, battery: battery, watchdog: watchdog)
service.boot()

// MARK: - CLI diagnostics (--probe / --selftest)
//
// Phase 3a: DispatchSemaphore bridges replaced with top-level await +
// withCheckedContinuation. stdout output is intentional (CLI report).

if CommandLine.arguments.contains("--probe") || CommandLine.arguments.contains("--selftest") {
    let cap: Capabilities = await withCheckedContinuation { cont in
        service.getCapabilities { cont.resume(returning: $0) }
    }
    print("fans=\(cap.fanCount) fanControl=\(cap.fanControl) ftst=\(cap.ftstPresent) battery=\(cap.batteryFamily) present=\(cap.batteryPresent) control=\(cap.batteryControl)")
    let probeKeys: [SMCKey] = [.ftstLower, .ftst, .fanMode(0), .fanModeLower(0), .chTE, .chIE, .ch0B, .ch0C, .b0AC]
    for key in probeKeys {
        let k = key.rawValue
        if let inf = try? smc.info(k) {
            let val = (try? smc.readBytes(k).1) ?? []
            print("key \(k) type=\(inf.typeFourCC) size=\(inf.dataSize) bytes=\(val.prefix(4).map { String(format: "%02x", $0) }.joined())")
        } else {
            print("key \(k) MISSING")
        }
    }

    let fanStatus: FanStatus = await withCheckedContinuation { cont in
        service.getFanStatus { cont.resume(returning: $0) }
    }
    for f in fanStatus.fans {
        print("fan\(f.index) rpm=\(Int(f.actualRPM)) min=\(Int(f.minRPM)) max=\(Int(f.maxRPM)) key=\(f.modeKey)")
    }

    let temps: [TempReading] = await withCheckedContinuation { cont in
        service.getThermalSnapshot { cont.resume(returning: $0) }
    }
    for t in temps { print("temp \(t.key)=\(Int(t.celsius.rounded()))C") }

    if CommandLine.arguments.contains("--selftest"), cap.fanControl {
        print("TEST quiet…")
        let quiet: (Bool, String?) = await withCheckedContinuation { cont in
            service.setFanMode(FanMode.quiet.rawValue) { ok, err in cont.resume(returning: (ok, err)) }
        }
        print("quiet ok=\(quiet.0) err=\(quiet.1 ?? "-")")
        try? await Task.sleep(for: .seconds(3))
        let afterQuiet: FanStatus = await withCheckedContinuation { cont in
            service.getFanStatus { cont.resume(returning: $0) }
        }
        for f in afterQuiet.fans { print("after-quiet fan\(f.index) rpm=\(Int(f.actualRPM))") }
        print("TEST restore system…")
        service.restoreAll()
        try? await Task.sleep(for: .seconds(1))

        print("TEST allow charging (CHTE=0)…")
        let charge: (Bool, String?) = await withCheckedContinuation { cont in
            service.setChargingEnabled(true) { ok, err in cont.resume(returning: (ok, err)) }
        }
        print("charge-enable ok=\(charge.0) err=\(charge.1 ?? "-")")
        try? await Task.sleep(for: .seconds(1))
        let bat: BatteryStatus = await withCheckedContinuation { cont in
            service.getBatteryStatus { cont.resume(returning: $0) }
        }
        print("battery after-enable \(bat.percent)% \(Int(bat.amperageMA))mA ac=\(bat.externalAC) family=\(bat.keyFamily)")
        print("SELFTEST done")
    } else {
        service.restoreAll()
    }
    exit(0)
}

// MARK: - Daemon run loop

signal(SIGTERM) { _ in
    NotificationCenter.default.post(name: Notification.Name("tc.stop"), object: nil)
}

NotificationCenter.default.addObserver(forName: Notification.Name("tc.stop"), object: nil, queue: nil) { _ in
    service.restoreAll()
    exit(0)
}

let listener = NSXPCListener(machServiceName: TC.machServiceName)
let xpcDelegate = HelperXPCDelegate(service: service)
listener.delegate = xpcDelegate
listener.resume()
Logger.helper.info("listening on \(TC.machServiceName, privacy: .public)")
RunLoop.main.run()