import CommandKit
import Foundation
import Testing

@testable import GujoAuthKit

/// 결정 7 — 사람 스태프 세션은 Keychain 이 아니라 Secure Enclave 키로 암호화한 파일에 둔다.
@Suite("SecureEnclaveFileSessionStore")
struct SecureEnclaveFileSessionStoreTests {
    /// 가역 변환으로 age 를 흉내 낸다(암호화는 앞에 표식을 붙이고 뒤집는다).
    static let fakeCipher: SecureEnclaveFileSessionStore.Cipher = { arguments, input in
        if arguments.first == "-d" {
            guard input.starts(with: Data("SEALED:".utf8)) else { return nil }
            return Data(input.dropFirst(7).reversed())
        }
        return Data("SEALED:".utf8) + Data(input.reversed())
    }

    func sandbox() throws -> (dir: URL, identity: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let identity = dir.appendingPathComponent("identity.txt")
        try Data("# created: now\n# public key: age1testrecipient\nAGE-PLUGIN-SE-1XYZ\n".utf8).write(to: identity)
        return (dir, identity)
    }

    @Test("저장하면 0600 파일에 암호문만 남고, 읽으면 평문을 돌려준다")
    func roundTrip() throws {
        let (dir, identity) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SecureEnclaveFileSessionStore(
            directory: dir.appendingPathComponent("sessions"),
            environment: [SecureEnclaveFileSessionStore.identityEnvironmentKey: identity.path],
            legacy: nil, cipher: Self.fakeCipher)

        #expect(store.recipient() == "age1testrecipient")
        #expect(store.setData(Data(#"{"token":"gst_x"}"#.utf8), account: "staff"))
        let file = store.file(for: "staff")
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let onDisk = try #require(FileManager.default.contents(atPath: file.path))
        #expect(!String(decoding: onDisk, as: UTF8.self).contains("gst_x"))
        #expect(store.data(account: "staff") == Data(#"{"token":"gst_x"}"#.utf8))

        store.delete(account: "staff")
        #expect(store.data(account: "staff") == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("옛 Keychain 항목은 첫 읽기에서 파일로 옮기고 Keychain 에서 지운다")
    func migratesLegacy() throws {
        let (dir, identity) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let legacy = InMemorySessionStore(initial: ["staff": Data("old".utf8)])
        let store = SecureEnclaveFileSessionStore(
            directory: dir.appendingPathComponent("sessions"),
            environment: [SecureEnclaveFileSessionStore.identityEnvironmentKey: identity.path],
            legacy: legacy, cipher: Self.fakeCipher)

        #expect(store.data(account: "staff") == Data("old".utf8))
        #expect(legacy.accounts.isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.file(for: "staff").path))
    }

    @Test("식별자가 없으면 저장하지 않는다(평문으로 떨어지지 않는다)")
    func refusesWithoutIdentity() throws {
        let (dir, _) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SecureEnclaveFileSessionStore(
            directory: dir.appendingPathComponent("sessions"),
            environment: [SecureEnclaveFileSessionStore.identityEnvironmentKey: dir.appendingPathComponent("missing").path],
            legacy: nil, cipher: Self.fakeCipher)
        #expect(!store.setData(Data("x".utf8), account: "staff"))
        #expect(!FileManager.default.fileExists(atPath: store.file(for: "staff").path))
    }

    @Test("실제 age 로 왕복한다(일반 X25519 키, age 가 없으면 건너뜀)")
    func realAgeRoundTrip() throws {
        let keygen = HostPlatformPaths.homebrewBin + "/age-keygen"
        guard FileManager.default.isExecutableFile(atPath: keygen) else { return }
        let (dir, _) = try sandbox()
        defer { try? FileManager.default.removeItem(at: dir) }
        let identity = dir.appendingPathComponent("x25519.txt")
        let generated = SafeProcessRunner.runSync(executable: keygen, arguments: ["-o", identity.path], timeout: 10)
        try #require(generated.exitCode == 0)
        let store = SecureEnclaveFileSessionStore(
            directory: dir.appendingPathComponent("sessions"),
            environment: [SecureEnclaveFileSessionStore.identityEnvironmentKey: identity.path],
            legacy: nil)
        #expect(store.setData(Data("real".utf8), account: "buyer"))
        let fresh = SecureEnclaveFileSessionStore(
            directory: dir.appendingPathComponent("sessions"),
            environment: [SecureEnclaveFileSessionStore.identityEnvironmentKey: identity.path],
            legacy: nil)
        #expect(fresh.data(account: "buyer") == Data("real".utf8))
    }
}
