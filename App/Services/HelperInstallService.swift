import AppKit
import Foundation
import ServiceManagement
import os

@MainActor
enum HelperInstallService {
    private static var cachedStatus: String = ""
    private static var lastCheckTime: Date = .distantPast

    static func statusText(force: Bool = false) -> String {
        if NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return "test"
        }
        if !force, Date().timeIntervalSince(lastCheckTime) < 10.0, !cachedStatus.isEmpty {
            return cachedStatus
        }
        if launchDaemonIsRunning() {
            cachedStatus = "enabled"
            lastCheckTime = Date()
            return cachedStatus
        }
        if #available(macOS 13.0, *) {
            let res: String
            switch SMAppService.daemon(plistName: TC.helperPlistName).status {
            case .enabled: res = "enabled"
            case .requiresApproval: res = "requiresApproval"
            case .notRegistered: res = "notRegistered"
            case .notFound: res = "notFound"
            @unknown default: res = "unknown"
            }
            cachedStatus = res
            lastCheckTime = Date()
            return res
        }
        return "unsupported"
    }

    static func needsUserApproval() -> Bool {
        if launchDaemonIsRunning() { return false }
        if #available(macOS 13.0, *) {
            let s = SMAppService.daemon(plistName: TC.helperPlistName).status
            return s == .requiresApproval || s == .notRegistered || s == .notFound
        }
        return true
    }

    /// Register the LaunchDaemon. `retrigger` unregisters first so macOS shows
    /// the "Allow in the Background" notification again.
    @discardableResult
    static func registerDaemon(retrigger: Bool = false) async -> String {
        if launchDaemonIsRunning() {
            return L10n.t("perm.registered")
        }
        if #available(macOS 13.0, *) {
            let svc = SMAppService.daemon(plistName: TC.helperPlistName)
            if retrigger {
                try? await svc.unregister()
                do { try await Task.sleep(for: .milliseconds(350)) }
                catch { return L10n.t("status.disconnected") }
            }
            do {
                try svc.register()
            } catch {
                let ns = error as NSError
                if ns.domain != "SMAppServiceErrorDomain" || ns.code != 1 {
                    Logger.install.error("register daemon failed: \(error.localizedDescription, privacy: .public)")
                    return L10n.t("install.fail")
                }
            }
            switch svc.status {
            case .enabled:
                return L10n.t("perm.registered")
            case .requiresApproval:
                return L10n.t("perm.approval")
            default:
                return L10n.t("install.register")
            }
        }
        return L10n.t("install.need13")
    }

    static func openLoginItems() {
        if #available(macOS 13.0, *) {
            SMAppService.openSystemSettingsLoginItems()
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    static func startAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// Shows the macOS admin-password dialog and installs the helper daemon.
    @discardableResult
    static func installWithAdministrator() async -> Bool {
        let helper = (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/MacOS/ThermalControlHelper")
        let script = Bundle.main.path(forResource: "install_helper", ofType: "sh")
            ?? ((Bundle.main.resourcePath as NSString?)?.appendingPathComponent("install_helper.sh"))
        guard FileManager.default.isExecutableFile(atPath: helper), let script, FileManager.default.fileExists(atPath: script) else {
            return false
        }
        let cmd = "bash \(shellEscape(script)) \(shellEscape(helper))"
        let source = "do shell script \(appleString(cmd)) with administrator privileges"
        // osascript runs outside the UI thread; macOS still owns the authorization dialog.
        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                Logger.install.error("installer failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }.value
    }

    static func launchDaemonIsRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["print", "system/\(TC.machServiceName)"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func setStartAtLogin(_ on: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if on { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                return true
            } catch {
                Logger.install.error("setStartAtLogin failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
        return false
    }
}
