import Security
import Testing
import RouseClosedLidProtocol

@Suite("Code-signing requirements")
struct CodeSigningRequirementTests {
    @Test func acceptedClientRequirementParsesAndSupportsStoreResigning() {
        let requirement = RouseClosedLidIPC.acceptedClientCodeSigningRequirement
        var parsedRequirement: SecRequirement?

        let status = SecRequirementCreateWithString(
            requirement as CFString,
            [],
            &parsedRequirement
        )

        #expect(status == errSecSuccess)
        #expect(parsedRequirement != nil)
        #expect(requirement.contains("com.apple.developer.team-identifier"))
        #expect(requirement.contains(RouseClosedLidIPC.appGroupIdentifier))
        #expect(requirement.contains(RouseClosedLidIPC.rouseBundleIdentifier))
        #expect(requirement.contains(RouseClosedLidIPC.helperBundleIdentifier))
    }

    @Test func daemonRequirementParsesAndPinsDeveloperIdentity() {
        let requirement = RouseClosedLidIPC.daemonCodeSigningRequirement
        var parsedRequirement: SecRequirement?

        let status = SecRequirementCreateWithString(
            requirement as CFString,
            [],
            &parsedRequirement
        )

        #expect(status == errSecSuccess)
        #expect(parsedRequirement != nil)
        #expect(requirement.contains(RouseClosedLidIPC.daemonBundleIdentifier))
        #expect(requirement.contains(RouseClosedLidIPC.teamIdentifier))
    }
}
