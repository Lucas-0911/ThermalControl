import Foundation
import os

/// SecCode-based authentication of incoming XPC connections: only callers
/// signed by the same Team ID as this helper are accepted.
///
/// Extracted verbatim from the old `HelperDelegate` god object (Phase 3c).
/// Logic is deliberately unchanged — weakening these checks would let any
/// local process drive the root SMC daemon.
enum ClientAuthenticator {
    /// Team IDs of this helper binary. Empty when unsigned (dev builds); in
    /// that case verification falls back to "accept" to keep `--probe` and
    /// unsigned dev workflows working, matching the historical behavior.
    static func ownTeams() -> Set<String> {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return [] }
        var sc: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &sc) == errSecSuccess, let sc else { return [] }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(sc, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let team = dict[kSecCodeInfoTeamIdentifier as String] as? String else { return [] }
        return [team]
    }

    static func verify(connection c: NSXPCConnection, teamIDs: Set<String>) -> Bool {
        var code: SecCode?
        var err = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: c.processIdentifier] as CFDictionary, [], &code)
        guard err == errSecSuccess, let code else { return teamIDs.isEmpty }
        var sc: SecStaticCode?
        err = SecCodeCopyStaticCode(code, [], &sc)
        guard err == errSecSuccess, let sc else { return false }
        var info: CFDictionary?
        err = SecCodeCopySigningInformation(sc, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        guard err == errSecSuccess, let dict = info as? [String: Any] else { return teamIDs.isEmpty }
        if teamIDs.isEmpty { return true }
        let team = dict[kSecCodeInfoTeamIdentifier as String] as? String
        return team.map { teamIDs.contains($0) } ?? false
    }
}