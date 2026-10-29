import AppKit

/// AppKit modal presenter. Owns the "one alert at a time" queueing flag.
/// ponytail: direct concrete class without ErrorPresenting protocol (YAGNI: single implementation).
@MainActor
final class AlertPresenter {
    enum PermissionChoice {
        case allow, sudo, later
    }

    private var alertQueued = false

    func presentError(_ message: String, title: String? = nil) {
        guard !alertQueued else { return }
        alertQueued = true
        let t = title ?? L10n.t("error.title")
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = t
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.t("ok"))
            alert.runModal()
            self?.alertQueued = false
        }
    }

    func confirmRestore(completion: @escaping () -> Void) {
        guard !alertQueued else { return }
        alertQueued = true
        DispatchQueue.main.async { [weak self] in
            let alert = NSAlert()
            alert.messageText = L10n.t("reset")
            alert.informativeText = L10n.t("reset.confirm")
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.t("reset"))
            alert.addButton(withTitle: L10n.t("cancel"))
            let confirmed = alert.runModal() == .alertFirstButtonReturn
            self?.alertQueued = false
            if confirmed { completion() }
        }
    }

    /// Three-button helper-installation dialog. The *decision* logic stays in
    /// the view model — this only renders and reports the choice.
    func presentHelperPermission(completion: @escaping (PermissionChoice) -> Void) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = L10n.t("perm.title")
            alert.informativeText = L10n.t("perm.body")
            alert.alertStyle = .informational
            alert.addButton(withTitle: L10n.t("perm.allow"))
            alert.addButton(withTitle: L10n.t("perm.sudo"))
            alert.addButton(withTitle: L10n.t("perm.later"))
            switch alert.runModal() {
            case .alertFirstButtonReturn: completion(.allow)
            case .alertSecondButtonReturn: completion(.sudo)
            default: completion(.later)
            }
        }
    }
}