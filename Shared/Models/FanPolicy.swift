import Foundation

/// Helper-internal fan policy. Lives in `Shared/` so the controller seams
/// (`FanControlling`) can be declared alongside the app target and faked in
/// tests; it never crosses the XPC boundary directly.
enum FanPolicy: Equatable {
    case system, quiet, max
    case manual(targets: [Int: Int])

    var modeRaw: Int {
        switch self {
        case .system: return FanMode.system.rawValue
        case .quiet: return FanMode.quiet.rawValue
        case .max: return FanMode.max.rawValue
        case .manual: return FanMode.manual.rawValue
        }
    }
}