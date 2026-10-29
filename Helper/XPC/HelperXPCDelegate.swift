import Foundation
import os

/// Vends `HelperXPCService` only to the signed app from this helper's team.
final class HelperXPCDelegate: NSObject, NSXPCListenerDelegate {
    private let service: HelperXPCService
    private let clientRequirement: String?

    init(service: HelperXPCService) {
        self.service = service
        self.clientRequirement = ClientAuthenticator.ownTeam().flatMap { ClientAuthenticator.clientRequirement(teamID: $0) }
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection c: NSXPCConnection) -> Bool {
        guard let clientRequirement else {
            Logger.helper.error("reject XPC client: helper signing identity unavailable or invalid")
            c.invalidate()
            return false
        }
        // Native macOS 13+ peer validation uses the connection's audit identity, not a reusable PID.
        // Set before resume/exported messages; Foundation rejects peers failing this requirement.
        c.setCodeSigningRequirement(clientRequirement)
        c.exportedInterface = ThermalXPC.makeInterface()
        c.exportedObject = service
        c.resume()
        return true
    }
}