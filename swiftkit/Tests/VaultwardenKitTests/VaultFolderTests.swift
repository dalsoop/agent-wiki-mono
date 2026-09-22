import XCTest
@testable import VaultwardenKit

/// 폴더 분류 계약 — 이름은 userKey 로 암호화해 올리고, 삭제해도 항목은 남는다.
final class VaultFolderTests: XCTestCase {
    private func makeKey() -> BitwardenCrypto.SymmetricKeySet {
        VaultAttachmentCrypto.makeAttachmentKey()
    }

    func testFolderNameEncryptsAndDecrypts() throws {
        let key = makeKey()
        for name in ["사업", "개인 금융", "서버/인프라", "Ops & 결제"] {
            let encrypted = try BitwardenCrypto.encryptString(name, key: key)
            // 서버에 올라가는 값은 평문이 아니다
            XCTAssertFalse(encrypted.contains(name))
            XCTAssertTrue(encrypted.hasPrefix("2."))
            XCTAssertEqual(try BitwardenCrypto.decryptString(encrypted, key: key), name)
        }
    }

    func testFolderDTODecodesBothCasings() throws {
        // 서버 구현에 따라 Id/Name 과 id/name 이 섞여 온다.
        let upper = #"{"Id":"f1","Name":"2.aaa|bbb|ccc"}"#
        let lower = #"{"id":"f2","name":"2.aaa|bbb|ccc"}"#
        let a = try JSONDecoder().decode(FolderDTO.self, from: Data(upper.utf8))
        let b = try JSONDecoder().decode(FolderDTO.self, from: Data(lower.utf8))
        XCTAssertEqual(a.id, "f1")
        XCTAssertEqual(b.id, "f2")
    }

    func testVaultFolderIdentity() {
        let folder = VaultFolder(id: "f1", name: "사업")
        XCTAssertEqual(folder.id, "f1")
        XCTAssertEqual(folder.name, "사업")
    }

    /// 항목 이동은 folderId 만 바꾼다 — 비밀 필드는 그대로여야 한다.
    func testMoveOnlyChangesFolderID() {
        var item = VaultItem(id: "i1", type: 1, name: "은행")
        item.username = "user"
        item.password = "pw"
        item.folderId = nil
        let before = (item.username, item.password, item.name)
        item.folderId = "f1"
        XCTAssertEqual(item.folderId, "f1")
        XCTAssertEqual(before.0, item.username)
        XCTAssertEqual(before.1, item.password)
        XCTAssertEqual(before.2, item.name)
    }
}
