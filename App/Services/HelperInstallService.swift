import AppKit
import Foundation
import ServiceManagement
import os

enum HelperInstallService {
    static func statusText() -> String {
        if #available(macOS 13.0, *) {
            switch SMAppService.daemon(plistName: TC.helperPlistName).status {
            case .enabled: return "enabled"
            case .requiresApproval: return "requiresApproval"
            case .notRegistered: return "notRegistered"
            case .notFound: return "notFound"
            @unknown default: return "unknown"
            }
        }
        return "unsupported"
    }

    static func needsUserApproval() -> Bool {
        if #available(macOS 13.0, *) {
            let s = SMAppService.daemon(plistName: TC.helperPlistName).status
            return s == .requiresApproval || s == .notRegistered || s == .notFound
        }
        return true
    }

    /// Register the LaunchDaemon. `retrigger` unregisters first so macOS shows
    /// the "Allow in the Background" notification again.
    @discardableResult
    static func registerDaemon(retrigger: Bool = false) -> String {
        if #available(macOS 13.0, *) {
            let svc = SMAppService.daemon(plistName: TC.helperPlistName)
            if retrigger {
                try? svc.unregister()
                Thread.sleep(forTimeInterval: 0.35)
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

    static func upgradeEmbeddedHelper() {
        _ = installWithAdministrator()
    }

    /// Shows the macOS admin-password dialog and installs the helper daemon.
    @discardableResult
    static func installWithAdministrator() -> Bool {
        let helper = (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/MacOS/ThermalControlHelper")
        let script = Bundle.main.path(forResource: "install_helper", ofType: "sh")
            ?? ((Bundle.main.resourcePath as NSString?)?.appendingPathComponent("install_helper.sh"))
        guard FileManager.default.isExecutableFile(atPath: helper), let script, FileManager.default.fileExists(atPath: script) else {
            return false
        }
        let cmd = "bash \(shellEscape(script)) \(shellEscape(helper))"
        let source = "do shell script \(appleString(cmd)) with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err {
            Logger.install.error("installWithAdministrator failed: \(err, privacy: .public)")
            return false
        }
        return true
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
