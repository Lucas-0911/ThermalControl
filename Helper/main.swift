import Foundation
import os

let smc = SMCService()
let transactionLock = NSRecursiveLock()
let fan = FanController(smc: smc, transactionLock: transactionLock)
let battery = BatteryController(smc: smc)
let watchdog = SafetyWatchdog(
    smc: smc,
    fan: fan,
    battery: battery,
    transactionLock: transactionLock
)
let service = HelperXPCService(
    smc: smc,
    fan: fan,
    battery: battery,
    watchdog: watchdog,
    transactionLock: transactionLock
)
let diagnostics = CommandLine.arguments.contains("--probe") || CommandLine.arguments.contains("--selftest")
if CommandLine.arguments.contains("--selftest"), !CommandLine.arguments.contains("--allow-hardware-writes") {
    fputs("--selftest changes hardware; explicit --allow-hardware-writes is required.\n", stderr)
    exit(2)
}
if diagnostics {
    do { try smc.open() }
    catch { fputs("SMC open failed: \(error)\n", stderr); exit(1) }
    fan.probe()
    battery.probe()
} else {
    service.boot()
}

// MARK: - CLI diagnostics (--probe / --selftest)

if diagnostics {
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

    var selfTestPassed = true
    if CommandLine.arguments.contains("--selftest"), cap.fanControl {
        print("TEST quiet…")
        let quiet: (Bool, String?) = await withCheckedContinuation { cont in
            service.setFanMode(FanMode.quiet.rawValue) { ok, err in cont.resume(returning: (ok, err)) }
        }
        print("quiet ok=\(quiet.0) err=\(quiet.1 ?? "-")")
        selfTestPassed = quiet.0
        try? await Task.sleep(for: .seconds(3))
        let afterQuiet: FanStatus = await withCheckedContinuation { cont in
            service.getFanStatus { cont.resume(returning: $0) }
        }
        for f in afterQuiet.fans { print("after-quiet fan\(f.index) rpm=\(Int(f.actualRPM))") }
        print("TEST restore system…")
        let restored = service.restoreAll()
        selfTestPassed = restored.0 && selfTestPassed
        try? await Task.sleep(for: .seconds(1))

        print("TEST allow charging (CHTE=0)…")
        let charge: (Bool, String?) = await withCheckedContinuation { cont in
            service.setChargingEnabled(true) { ok, err in cont.resume(returning: (ok, err)) }
        }
        print("charge-enable ok=\(charge.0) err=\(charge.1 ?? "-")")
        selfTestPassed = charge.0 && selfTestPassed
        try? await Task.sleep(for: .seconds(1))
        let bat: BatteryStatus = await withCheckedContinuation { cont in
            service.getBatteryStatus { cont.resume(returning: $0) }
        }
        print("battery after-enable \(bat.percent)% \(Int(bat.amperageMA))mA ac=\(bat.externalAC) family=\(bat.keyFamily)")
        print("SELFTEST done")
    } else if CommandLine.arguments.contains("--selftest") {
        selfTestPassed = false
    }
    if CommandLine.arguments.contains("--selftest") {
        let cleanup = service.restoreAll()
        selfTestPassed = cleanup.0 && selfTestPassed
    }
    smc.close()
    exit(selfTestPassed ? 0 : 1)
}

// MARK: - Daemon run loop

signal(SIGTERM) { _ in
    NotificationCenter.default.post(name: Notification.Name("tc.stop"), object: nil)
}

NotificationCenter.default.addObserver(forName: Notification.Name("tc.stop"), object: nil, queue: nil) { _ in
    let result = service.prepareForShutdown()
    exit(result.succeeded ? 0 : 1)
}

let listener = NSXPCListener(machServiceName: TC.machServiceName)
let xpcDelegate = HelperXPCDelegate(service: service)
listener.delegate = xpcDelegate
listener.resume()
Logger.helper.info("listening on \(TC.machServiceName, privacy: .public)")
dispatchMain()