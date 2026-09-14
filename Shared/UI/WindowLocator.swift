import AppKit

/// Single place for finding the dashboard window by title.
/// Previously duplicated with subtle differences in `MenuBarView.mainWindow()`
/// and `ThermalViewModel.openDashboard()`.
enum WindowLocator {
    static let dashboardTitle = "Thermal Control"

    /// The main dashboard `NSWindow`: matches the title, is main-able and is
    /// NOT the menu-bar extra's `.nonactivatingPanel`.
    static func dashboardWindow() -> NSWindow? {
        NSApp.windows.first { win in
            guard win.title == dashboardTitle else { return false }
            guard win.canBecomeMain else { return false }
            guard !win.styleMask.contains(.nonactivatingPanel) else { return false }
            return true
        }
    }

    static func bringDashboardForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let existing = dashboardWindow() {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
        }
    }
}