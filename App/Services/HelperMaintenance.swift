import Foundation
import ServiceManagement

/// Explicit signed-app maintenance entrypoints. Normal launch never runs these.
@MainActor
enum HelperMaintenance {
    static func isRequested(_ arguments: [String]) -> Bool {
        let flags: Set<String> = [
            "--restore-system-control", "--release-transient-control", "--migrate-legacy-helper", "--restore-legacy-control",
            "--register-helper", "--unregister-helper", "--helper-status", "--set-charge-limit", "--test-fan-ramp"
        ]
        return arguments.contains { flags.contains($0) }
    }

    static func chargeLimits(in arguments: [String]) -> ChargeLimits? {
        guard let index = arguments.firstIndex(of: "--set-charge-limit"), arguments.count == index + 3,
              let upper = Int(arguments[index + 1]), let lower = Int(arguments[index + 2]),
              (ChargeLimits.minUpper...ChargeLimits.maxPercent).contains(upper),
              lower >= ChargeLimits.minPercent, lower <= upper - ChargeLimits.minGap else { return nil }
        return ChargeLimits(upper: upper, lower: lower)
    }

    static func restored(fan: FanStatus?, battery: BatteryStatus?, capabilities: Capabilities) -> Bool {
        if capabilities.fanCount > 0 {
            guard let fan, fan.desiredMode == FanMode.system.rawValue,
                  fan.fans.count == capabilities.fanCount,
                  fan.fans.allSatisfy({ $0.modeRaw == 0 }), fan.lastError?.isEmpty != false else { return false }
        }
        if capabilities.batteryPresent {
            guard let battery, !battery.forceDischarge, !battery.maintainActive,
                  battery.chargingEnabled,
                  battery.lastError?.isEmpty != false else { return false }
        }
        return true
    }

    static func run(arguments: [String]) async -> Int32 {
        guard arguments.filter({ $0.hasPrefix("--") }).count == 1 else {
            fputs("Exactly one maintenance operation is required.\n", stderr)
            return 2
        }
        if arguments.contains("--register-helper") {
            let service = SMAppService.daemon(plistName: TC.helperPlistName)
            do {
                try service.register()
                print("registration=\(service.status.rawValue)")
                return service.status == .enabled ? 0 : 3
            } catch {
                fputs("Helper registration failed: \(error)\n", stderr)
                return 1
            }
        }
        let client = XPCClient()
        client.connect()
        defer { client.invalidate() }
        guard let cap = await client.capabilities() else {
            fputs("Helper handshake failed; no changes made.\n", stderr)
            return 2
        }
        if arguments.contains("--unregister-helper") {
            // Protocol 3 introduced the same component-release selector used for this update bridge.
            guard cap.protocolVersion == 3 || cap.protocolVersion == TC.protocolVersion else {
                fputs("Unsupported helper release contract; registration unchanged.\n", stderr)
                return 2
            }
            let released = await client.restore(components: RestoreResult.transient)
            guard released.succeeded else { fputs("Transient release failed: \(released.message ?? "unknown")\n", stderr); return 1 }
            do {
                try await SMAppService.daemon(plistName: TC.helperPlistName).unregister()
                print("Transient control released; native helper unregistered. Saved charge intent retained.")
                return 0
            } catch {
                fputs("Native unregister failed: \(error)\n", stderr)
                return 1
            }
        }
        if arguments.contains("--helper-status") {
            print("helper=\(cap.helperVersion) protocol=\(cap.protocolVersion) fanControl=\(cap.fanControl) batteryControl=\(cap.batteryControl)")
            if let fan = await client.fanStatus() {
                print("fanMode=\(fan.desiredMode) ramping=\(fan.ramping) transition=\(fan.transitionID) fans=\(fan.fans.map { "\($0.index):actual=\($0.actualRPM) target=\($0.targetRPM) goal=\($0.goalRPM) min=\($0.minRPM) max=\($0.maxRPM) mode=\($0.modeRaw)" }.joined(separator: ","))")
            }
            if let battery = await client.batteryStatus() {
                print("battery=\(battery.percent) AC=\(battery.externalAC) maintain=\(battery.maintainActive) upper=\(battery.upperLimit) lower=\(battery.lowerLimit) charging=\(battery.chargingEnabled) discharge=\(battery.forceDischarge) stopRegisterVerified=\(battery.dischargeStopVerified) error=\(battery.lastError ?? "none")")
            }
            return 0
        }
        if arguments.contains("--migrate-legacy-helper") || arguments.contains("--restore-legacy-control") {
            // ponytail: only protocol 2 has a known legacy restore contract; reject all other versions.
            guard cap.protocolVersion == 2 else {
                fputs("Migration requires legacy protocol 2; registration unchanged.\n", stderr)
                return 2
            }
            let result = await client.restore()
            guard result.0 else { fputs("Legacy restore failed: \(result.1 ?? "unknown")\n", stderr); return 1 }
            let fan = await client.fanStatus()
            let battery = await client.batteryStatus()
            guard restored(fan: fan, battery: battery, capabilities: cap) else {
                fputs("Legacy restore readback not confirmed; registration unchanged.\n", stderr)
                return 1
            }
            if arguments.contains("--restore-legacy-control") {
                print("Legacy restore confirmed; registration unchanged.")
                return 0
            }
            do {
                try await SMAppService.daemon(plistName: TC.helperPlistName).unregister()
                print("Legacy restore confirmed; native helper registration removed.")
                return 0
            } catch {
                fputs("Native helper unregister failed: \(error)\n", stderr)
                return 1
            }
        }
        if arguments.contains("--test-fan-ramp") {
            guard cap.protocolVersion == TC.protocolVersion else { return 2 }
            let result = await client.setFanMode(.max)
            var verified = result.0
            print("maxAccepted=\(result.0) error=\(result.1 ?? "none")")
            for _ in 0..<12 {
                if let fan = await client.fanStatus() {
                    print("ramping=\(fan.ramping) mode=\(fan.desiredMode) error=\(fan.lastError ?? "none") " + fan.fans.map {
                        "fan\($0.index) target=\($0.targetRPM) actual=\($0.actualRPM) goal=\($0.goalRPM)"
                    }.joined(separator: "; "))
                    if fan.lastError != nil { verified = false; break }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            let released = await client.restore(components: RestoreResult.transient)
            if let message = released.message { fputs("Release: \(message)\n", stderr) }
            return verified && released.succeeded ? 0 : 1
        }
        guard cap.protocolVersion == TC.protocolVersion,
              let limits = chargeLimits(in: arguments) else {
            fputs("Invalid limits or incompatible helper; no write submitted.\n", stderr)
            return 2
        }
        let result = await client.setChargeLimit(upper: limits.upper, lower: limits.lower)
        guard result.0, let status = await client.batteryStatus(),
              status.maintainActive, status.upperLimit == limits.upper, status.lowerLimit == limits.lower,
              !status.forceDischarge, status.dischargeStopVerified, status.lastError?.isEmpty != false else {
            fputs("Charge policy not confirmed: \(result.1 ?? "readback failed")\n", stderr)
            return 1
        }
        print("Confirmed charge limits \(limits.upper)/\(limits.lower); discharge off.")
        return 0
    }
}
