import Foundation

/// Helper-internal fan policy. Lives in `Shared/` so the controller seams
/// (`FanControlling`) can be declared alongside the app target and faked in
/// tests; it never crosses the XPC boundary directly.
enum FanPolicy: Equatable {
    case system, quiet, max
    case manual(targets: [Int: Int])
}