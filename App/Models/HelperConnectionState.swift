import Foundation

enum HelperConnectionState: String {
    case disconnected, connecting, connected, needsApproval, error, restoring
}
