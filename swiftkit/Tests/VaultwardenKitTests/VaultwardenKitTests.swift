import XCTest
@testable import VaultwardenKit

final class CryptoTests: XCTestCase {
    func testMasterKeyEmailNormalized() throws {
        let kdf = BitwardenCrypto.KdfConfig(kdf: 0, iterations: 100_000)
        let a = try BitwardenCrypto.masterKey(password: "pw", email: "Test@Example.com", kdf: kdf)
        let b = try BitwardenCrypto.masterKey(password: "pw", email: "test@example.com ", kdf: kdf)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 32)
    }

    func testUnsupportedKdf() {
        let kdf = BitwardenCrypto.KdfConfig(kdf: 1, iterations: 3)
        XCTAssertThrowsError(try BitwardenCrypto.masterKey(password: "x", email: "a@b.c", kdf: kdf))
    }

    func testEncStringRoundTrip() throws {
        let key = BitwardenCrypto.stretchedKey(masterKey: Data(repeating: 7, count: 32))
        let s = "슈퍼비밀-Password!@#"
        let enc = try BitwardenCrypto.encryptString(s, key: key)
        XCTAssertTrue(enc.hasPrefix("2."))
        XCTAssertEqual(try BitwardenCrypto.decryptString(enc, key: key), s)
    }

    func testMacTamperFails() throws {
        let key = BitwardenCrypto.stretchedKey(masterKey: Data(repeating: 9, count: 32))
        let enc = try BitwardenCrypto.encrypt(Data("hi".utf8), key: key)
        var mac = enc.mac!; mac[0] ^= 0xFF
        let bad = BitwardenCrypto.EncString(type: 2, iv: enc.iv, data: enc.data, mac: mac)
        XCTAssertThrowsError(try BitwardenCrypto.decrypt(bad, key: key))
    }
}

final class GeneratorTests: XCTestCase {
    func testLengthAndCharset() {
        XCTAssertEqual(PasswordGenerator.generate(.init(length: 32)).count, 32)
        let digits = PasswordGenerator.generate(.init(length: 30, useLowercase: false, useUppercase: false, useDigits: true, useSymbols: false))
        XCTAssertTrue(digits.allSatisfy { $0.isNumber })
    }
    func testDiffers() {
        XCTAssertNotEqual(PasswordGenerator.generate(.init()), PasswordGenerator.generate(.init()))
    }
}

final class ClientTests: XCTestCase {
    func testEndpointSelfHosted() throws {
        let ep = try ServerEndpoint.selfHosted("vault.example.com/")
        XCTAssertEqual(ep.identity, "https://vault.example.com/identity")
        XCTAssertEqual(ep.api, "https://vault.example.com/api")
    }
    func testCloudPresets() {
        XCTAssertEqual(ServerEndpoint.cloudUS.identity, "https://identity.bitwarden.com")
        XCTAssertEqual(ServerEndpoint.cloudEU.api, "https://api.bitwarden.eu")
    }
    func testVaultItemSearch() {
        let i = VaultItem(name: "GitHub", username: "me", uri: "github.com", notes: "2FA backup")
        XCTAssertTrue(i.matches("git"))
        XCTAssertFalse(i.matches("gitlab"))
        XCTAssertTrue(i.matches("2FA"))
        var tagged = i
        tagged.tags = ["망:인터넷", "테넌트:ranode"]
        XCTAssertTrue(tagged.matches("ranode"))
    }

    func testMatchesExactAndSubdomainButNotLookalike() {
        let item = VaultItem(uri: "https://naver.com/login")

        XCTAssertTrue(item.matchesLoginHost("naver.com"))
        XCTAssertTrue(item.matchesLoginHost("nid.naver.com"))
        XCTAssertFalse(item.matchesLoginHost("evilnaver.com"))
        XCTAssertFalse(item.matchesLoginHost("naver.com.evil.example"))
    }

    func testLoginHostMatcherNormalizesCaseAndBareDomains() {
        let item = VaultItem(uri: "NAVER.COM/account")

        XCTAssertTrue(item.matchesLoginHost("NID.NAVER.COM"))
        XCTAssertFalse(item.matchesLoginHost(""))
    }
}

final class BitwardenCLITests: XCTestCase {
    func testRunResultPreservesExitStatus() async {
        let cli = BitwardenCLI()
        let success = await cli.runResult("/usr/bin/printf", ["safe-output"])
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.output, "safe-output")

        let failure = await cli.runResult("/usr/bin/false", [])
        XCTAssertFalse(failure.ok)
        XCTAssertNotEqual(failure.exitCode, 0)
    }
}
