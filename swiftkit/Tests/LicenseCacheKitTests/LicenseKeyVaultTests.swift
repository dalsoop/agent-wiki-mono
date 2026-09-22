import Foundation
import Testing
@testable import LicenseCacheKit

@Suite("LicenseKeyVault")
struct LicenseKeyVaultTests {
    @Test("set then get then list round-trips the same record")
    func setGetListRoundTrip() throws {
        let vault = LicenseKeyVault(store: MemoryLicenseSecretStore())
        try vault.set(
            service: "net.ranode.sample",
            displayName: "Sample",
            key: "KEY-ABCD-1234",
            note: "note"
        )
        let got = try vault.get(service: "net.ranode.sample")
        #expect(got?.licenseKey == "KEY-ABCD-1234")
        #expect(got?.displayName == "Sample")
        #expect(got?.note == "note")
        #expect(got?.maskedKey.hasSuffix("1234") == true)

        let listed = try vault.list()
        #expect(listed.count == 1)
        #expect(listed[0].service == "net.ranode.sample")
    }

    @Test("set replaces the same service and delete removes it")
    func replaceAndDelete() throws {
        let vault = LicenseKeyVault(store: MemoryLicenseSecretStore())
        try vault.set(service: "net.ranode.a", displayName: "A", key: "old")
        try vault.set(service: "net.ranode.a", displayName: "A", key: "new")
        #expect(try vault.get(service: "net.ranode.a")?.licenseKey == "new")
        #expect(try vault.list().count == 1)
        try vault.delete(service: "net.ranode.a")
        #expect(try vault.get(service: "net.ranode.a") == nil)
        #expect(try vault.list().isEmpty)
    }

    @Test("empty service or key is rejected")
    func rejectsEmpty() throws {
        let vault = LicenseKeyVault(store: MemoryLicenseSecretStore())
        #expect(throws: LicenseKeyVaultError.emptyService) {
            try vault.set(service: "  ", displayName: "x", key: "k")
        }
        #expect(throws: LicenseKeyVaultError.emptyKey) {
            try vault.set(service: "net.ranode.a", displayName: "x", key: " ")
        }
    }
}
