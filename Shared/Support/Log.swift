import os

/// App-wide `os.Logger` instances grouped by subsystem/category so Console.app
/// can filter diagnostics. Replaces ad-hoc `NSLog`/`print` call sites.
///
/// `Shared/` is compiled into BOTH the app target and the helper daemon target,
/// so the categories below cover both processes.
public extension Logger {
    private static let subsystem = TC.appBundleID

    static let smc = Logger(subsystem: subsystem, category: "smc")
    static let fan = Logger(subsystem: subsystem, category: "fan")
    static let battery = Logger(subsystem: subsystem, category: "battery")
    static let xpc = Logger(subsystem: subsystem, category: "xpc")
    static let watchdog = Logger(subsystem: subsystem, category: "watchdog")
    static let helper = Logger(subsystem: subsystem, category: "helper")
    static let install = Logger(subsystem: subsystem, category: "install")
    static let power = Logger(subsystem: subsystem, category: "power")
    static let state = Logger(subsystem: subsystem, category: "state")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}