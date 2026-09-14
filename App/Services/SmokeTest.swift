import Foundation

enum SmokeTest {
    static func runAndExit() {
        print("== local sensors (no helper) ==")
        let bat = SensorReader.battery()
        print("battery present=\(bat.present) percent=\(bat.percent) ac=\(bat.ac) mA=\(Int(SensorReader.amperageMA()))")
        let fans = SensorReader.fans()
        if fans.isEmpty {
            print("fans: none")
        } else {
            for f in fans {
                print("fan\(f.index) rpm=\(Int(f.actualRPM)) min=\(Int(f.minRPM)) max=\(Int(f.maxRPM))")
            }
        }
        let temps = SensorReader.temps()
        if temps.isEmpty {
            print("temps: none")
        } else {
            for t in temps { print("temp \(t.key)=\(Int(t.celsius.rounded()))C") }
        }

        print("== helper XPC ==")
        let xpc = XPCClient()
        xpc.connect()

        guard waitBool({ xpc.ping($0) }, timeout: 3) == true else {
            fputs("FAIL: helper ping (daemon chưa cài hoặc XPC bị chặn)\n", stderr)
            exit(2)
        }
        print("ping=ok")

        let cap = waitValue { xpc.capabilities($0) }
        guard let cap else {
            fputs("FAIL: capabilities\n", stderr)
            exit(1)
        }
        print("helper v\(cap.helperVersion) fans=\(cap.fanCount) fanControl=\(cap.fanControl) battery=\(cap.batteryFamily) batteryControl=\(cap.batteryControl)")

        if let st = waitValue({ xpc.fanStatus($0) }) {
            for f in st.fans {
                print("xpc fan\(f.index) rpm=\(Int(f.actualRPM))")
            }
        }
        if let b = waitValue({ xpc.batteryStatus($0) }) {
            print("xpc battery \(b.percent)% \(Int(b.amperageMA))mA ac=\(b.externalAC)")
        }
        let xt = waitTemps { xpc.temps($0) }
        for t in xt { print("xpc temp \(t.key)=\(Int(t.celsius.rounded()))C") }

        if cap.fanControl {
            print("TEST set Quiet")
            let (ok, err) = waitPair { xpc.setFanMode(.quiet, $0) }
            print("quiet ok=\(ok) err=\(err ?? "-")")
            Thread.sleep(forTimeInterval: 3)
            if let st = waitValue({ xpc.fanStatus($0) }) {
                for f in st.fans { print("after-quiet fan\(f.index) rpm=\(Int(f.actualRPM))") }
            }
            let (rok, rerr) = waitPair { xpc.restore($0) }
            print("restore ok=\(rok) err=\(rerr ?? "-")")
        }

        print("SMOKE TEST PASS")
        exit(0)
    }

    private static func waitBool(_ call: (@escaping (Bool) -> Void) -> Void, timeout: TimeInterval) -> Bool? {
        let sem = DispatchSemaphore(value: 0)
        var out: Bool?
        call { v in out = v; sem.signal() }
        if sem.wait(timeout: .now() + timeout) == .timedOut { return nil }
        return out
    }

    private static func waitValue<T>(_ call: (@escaping (T?) -> Void) -> Void) -> T? {
        let sem = DispatchSemaphore(value: 0)
        var out: T?
        call { v in out = v; sem.signal() }
        _ = sem.wait(timeout: .now() + 4)
        return out
    }

    private static func waitTemps(_ call: (@escaping ([TempReading]) -> Void) -> Void) -> [TempReading] {
        let sem = DispatchSemaphore(value: 0)
        var out: [TempReading] = []
        call { v in out = v; sem.signal() }
        _ = sem.wait(timeout: .now() + 4)
        return out
    }

    private static func waitPair(_ call: (@escaping (Bool, String?) -> Void) -> Void) -> (Bool, String?) {
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        var err: String?
        call { a, b in ok = a; err = b; sem.signal() }
        _ = sem.wait(timeout: .now() + 15)
        return (ok, err)
    }
}
