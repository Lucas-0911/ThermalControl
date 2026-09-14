import Foundation
import os

let delegate = HelperDelegate()

if CommandLine.arguments.contains("--probe") || CommandLine.arguments.contains("--selftest") {
    let capWait = DispatchSemaphore(value: 0)
    var capRef: Capabilities?
    delegate.getCapabilities { cap in
        capRef = cap
        print("fans=\(cap.fanCount) fanControl=\(cap.fanControl) ftst=\(cap.ftstPresent) battery=\(cap.batteryFamily) present=\(cap.batteryPresent) control=\(cap.batteryControl)")
        let smc = delegate.smc
        for k in ["Ftst", "FTST", "F0Md", "F0md", "CHTE", "CHIE", "CH0B", "CH0C", "B0AC"] {
            if let inf = try? smc.info(k) {
                let val = (try? smc.readBytes(k).1) ?? []
                print("key \(k) type=\(inf.typeFourCC) size=\(inf.dataSize) bytes=\(val.prefix(4).map { String(format: "%02x", $0) }.joined())")
            } else {
                print("key \(k) MISSING")
            }
        }
        capWait.signal()
    }
    _ = capWait.wait(timeout: .now() + 2)

    let fanWait = DispatchSemaphore(value: 0)
    delegate.getFanStatus { st in
        for f in st.fans {
            print("fan\(f.index) rpm=\(Int(f.actualRPM)) min=\(Int(f.minRPM)) max=\(Int(f.maxRPM)) key=\(f.modeKey)")
        }
        fanWait.signal()
    }
    _ = fanWait.wait(timeout: .now() + 2)

    let tmpWait = DispatchSemaphore(value: 0)
    delegate.getThermalSnapshot { list in
        for t in list { print("temp \(t.key)=\(Int(t.celsius.rounded()))C") }
        tmpWait.signal()
    }
    _ = tmpWait.wait(timeout: .now() + 2)

    if CommandLine.arguments.contains("--selftest"), capRef?.fanControl == true {
        print("TEST quiet…")
        let q = DispatchSemaphore(value: 0)
        delegate.setFanMode(FanMode.quiet.rawValue) { ok, err in
            print("quiet ok=\(ok) err=\(err ?? "-")")
            q.signal()
        }
        _ = q.wait(timeout: .now() + 15)
        Thread.sleep(forTimeInterval: 3)
        let after = DispatchSemaphore(value: 0)
        delegate.getFanStatus { st in
            for f in st.fans { print("after-quiet fan\(f.index) rpm=\(Int(f.actualRPM))") }
            after.signal()
        }
        _ = after.wait(timeout: .now() + 2)
        print("TEST restore system…")
        delegate.restoreAll()
        Thread.sleep(forTimeInterval: 1)

        print("TEST allow charging (CHTE=0)…")
        let ch = DispatchSemaphore(value: 0)
        delegate.setChargingEnabled(true) { ok, err in
            print("charge-enable ok=\(ok) err=\(err ?? "-")")
            ch.signal()
        }
        _ = ch.wait(timeout: .now() + 4)
        Thread.sleep(forTimeInterval: 1)
        let bst = DispatchSemaphore(value: 0)
        delegate.getBatteryStatus { st in
            print("battery after-enable \(st.percent)% \(Int(st.amperageMA))mA ac=\(st.externalAC) family=\(st.keyFamily)")
            bst.signal()
        }
        _ = bst.wait(timeout: .now() + 2)
        print("SELFTEST done")
    } else {
        delegate.restoreAll()
    }
    exit(0)
}

signal(SIGTERM) { _ in
    NotificationCenter.default.post(name: Notification.Name("tc.stop"), object: nil)
}

NotificationCenter.default.addObserver(forName: Notification.Name("tc.stop"), object: nil, queue: nil) { _ in
    delegate.restoreAll()
    exit(0)
}

let listener = NSXPCListener(machServiceName: TC.machServiceName)
listener.delegate = delegate
listener.resume()
Logger.helper.info("listening on \(TC.machServiceName, privacy: .public)")
RunLoop.main.run()
