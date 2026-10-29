import Foundation

/// Test seam between feature view models and lifecycle/error presentation.
@MainActor
protocol ViewModelHost: AnyObject {
    /// True while startup is actively establishing the helper connection.
    var isConnecting: Bool { get }

    /// Mirrors the old `controlsEnabled` (connectionState == .connected).
    var isConnected: Bool { get }

    /// Inline error text only (no modal) — matches the old `lastError = err`
    /// sites fed by status polling.
    func noteError(_ message: String)

    /// Inline error text + modal alert — matches the old `presentError(...)`
    /// sites fed by command failures.
    func surfaceError(_ message: String)

    /// Matches the old `lastError = nil` on command success.
    func clearError()

    /// Charge state changed → burst-sample the power charts (old
    /// `burstPowerSamples()` call sites).
    func batteryChargeDidChange()
}