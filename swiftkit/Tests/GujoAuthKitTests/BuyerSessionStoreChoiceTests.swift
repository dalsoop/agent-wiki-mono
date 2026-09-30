import Foundation
import Testing

@testable import GujoAuthKit

/// 구매자 세션 저장소의 의도적 차이 — 운영자 맥(SE 식별자 있음)은 암호 파일, 구매자 맥은 Keychain.
@Suite("GujoSessionStores.buyer")
struct BuyerSessionStoreChoiceTests {
    @Test("SE 식별자가 있으면 암호 파일 저장소를 고른다")
    func operatorMacUsesSealedFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let identity = dir.appendingPathComponent("identity.txt")
        try Data("# access control: none\n# public key: age1se1testrecipient\nAGE-PLUGIN-SE-1XYZ\n".utf8)
            .write(to: identity)

        let store = GujoSessionStores.buyer(
            environment: [SecureEnclaveFileSessionStore.identityEnvironmentKey: identity.path],
            home: dir.path)

        #expect(store is SecureEnclaveFileSessionStore)
    }

    @Test("SE 식별자가 없으면 Keychain 을 쓴다(구매자 맥)")
    func buyerMacUsesKeychain() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = GujoSessionStores.buyer(environment: [:], home: dir.path)

        #expect(store is KeychainSessionStore)
    }
}
