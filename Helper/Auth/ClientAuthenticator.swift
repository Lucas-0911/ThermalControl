import Foundation
import Security

/// The root helper and its XPC clients must have valid Apple-issued signatures.
enum ClientAuthenticator {
    static func clientRequirement(teamID: String) -> String? {
        // Team IDs are ten ASCII letters/digits; reject requirement-language injection.
        guard teamID.utf8.count == 10,
              teamID.utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }) else { return nil }
        return "anchor apple generic and identifier \"com.thermalcontrol.app\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    static func ownTeam() -> String? {
        var code: SecCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(
                "anchor apple generic and identifier \"com.thermalcontrol.helper\"" as CFString,
                [], &requirement
              ) == errSecSuccess, let requirement,
              SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { return nil }

        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
              clientRequirement(teamID: team) != nil else { return nil }
        return team
    }
}
