import Security
import XCTest

final class ClientAuthenticatorTests: XCTestCase {
    func testTestRunnerCannotSupplyHelperIdentity() {
        XCTAssertNil(ClientAuthenticator.ownTeam())
    }

    func testRejectsMissingOrMalformedTeamIDs() {
        for team in ["", " ", "M9GD64VJ5", "M9GD64VJ5RX", "m9gd64vj5r", "M9GD64VJ5é", "M9GD64VJ5\" or true"] {
            XCTAssertNil(ClientAuthenticator.clientRequirement(teamID: team), team)
        }
    }

    func testRequirementPinsAppAndTeamAndRequiresAppleSignature() throws {
        let text = try XCTUnwrap(ClientAuthenticator.clientRequirement(teamID: "M9GD64VJ5R"))
        XCTAssertEqual(text, "anchor apple generic and identifier \"com.thermalcontrol.app\" and certificate leaf[subject.OU] = \"M9GD64VJ5R\"")
        var requirement: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess)
        XCTAssertNotNil(requirement)
    }

    func testNativeVerificationRejectsSignedNonAppForBothTeams() throws {
        let code = try systemCode()
        XCTAssertEqual(SecStaticCodeCheckValidity(code, [], nil), errSecSuccess)
        for team in ["M9GD64VJ5R", "AAAAAAAAAA"] {
            let text = try XCTUnwrap(ClientAuthenticator.clientRequirement(teamID: team))
            var requirement: SecRequirement?
            XCTAssertEqual(SecRequirementCreateWithString(text as CFString, [], &requirement), errSecSuccess)
            XCTAssertNotEqual(SecStaticCodeCheckValidity(code, [], try XCTUnwrap(requirement)), errSecSuccess)
        }
    }

    func testNativeVerificationRejectsTruncatedSignedExecutable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("invalid-client")
        let bytes = try Data(contentsOf: URL(fileURLWithPath: "/usr/bin/true"))
        try bytes.prefix(bytes.count / 2).write(to: executable)
        var code: SecStaticCode?
        let status = SecStaticCodeCreateWithPath(executable as CFURL, [], &code)
        if status == errSecSuccess, let code {
            XCTAssertNotEqual(SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil), errSecSuccess)
        } else {
            XCTAssertNotEqual(status, errSecSuccess)
        }
    }

    private func systemCode() throws -> SecStaticCode {
        var code: SecStaticCode?
        XCTAssertEqual(SecStaticCodeCreateWithPath(URL(fileURLWithPath: "/usr/bin/true") as CFURL, [], &code), errSecSuccess)
        return try XCTUnwrap(code)
    }
}
