import Foundation
import os

/// `NSXPCListenerDelegate` — accepts connections only from same-Team-ID
/// callers (`ClientAuthenticator`) and vends `HelperXPCService`.
/// Split out of the old `HelperDelegate` god object (Phase 3c).
final class HelperXPCDelegate: NSObject, NSXPCListenerDelegate {
    private let service: HelperXPCService
    private let teamIDs: Set<String>

    init(service: HelperXPCService) {
        self.service = service
        self.teamIDs = ClientAuthenticator.ownTeams()
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        guard ClientAuthenticator.verify(connection: c, teamIDs: teamIDs) else {
            Logger.helper.warning("reject pid=\(c.processIdentifier, privacy: .public) team mismatch or unsigned")
            c.invalidate()
            return false
        }
        c.exportedInterface = ThermalXPC.makeInterface()
        c.exportedObject = service
        c.resume()
        return true
    }
}