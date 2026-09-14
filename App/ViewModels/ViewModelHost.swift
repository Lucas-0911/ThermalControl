import Foundation

/// Coordinator seam between the feature view models and the orchestrating
/// `ThermalViewModel`. Errors are *reported up* instead of the view models
/// driving `NSAlert` themselves (Phase 4: presentation leaves the business
/// layer — `AlertPresenter` is owned by the orchestrator).
@MainActor
protocol ViewModelHost: AnyObject {
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