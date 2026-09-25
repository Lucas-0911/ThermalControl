import AppKit

/// Abstraction the view models depend on for surfacing errors, so no
/// `NSAlert`/`NSApp` calls remain in the business layer (Phase 4).
@MainActor
protocol ErrorPresenting {
    func presentError(_ message: String, title: String?)
}

/// AppKit modal presenter. Owns the "one alert at a time" queueing flag that
/// used to live in `ThermalViewModel`.
@MainActor
final class AlertPresenter: ErrorPresenting {
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