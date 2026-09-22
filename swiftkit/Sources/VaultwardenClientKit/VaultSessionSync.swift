import Foundation

extension VaultSession {
    public func syncItems() async throws -> [VaultItem] {
        try await syncVault().items
    }

    /// 전체 동기화: 폴더 + 전 타입(로그인/노트/카드/신원) + 휴지통 포함.
    public func syncVault() async throws -> (folders: [VaultFolder], items: [VaultItem]) {
        let (client, token, key) = try requireUnlocked()
        let sync = try await client.sync(token: token)
        let folders = sync.folders.compactMap { f -> VaultFolder? in
            guard let id = f.id, let enc = f.name,
                  let name = try? BitwardenCrypto.decryptString(enc, key: key) else { return nil }
            return VaultFolder(id: id, name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let items = sync.ciphers
            .compactMap { VaultCipherCodec.decrypt($0, userKey: key) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (folders, items)
    }

    /// 소속 조직과 컬렉션 — 조직 키로 컬렉션 이름을 푼다.
    /// 조직 키는 sync 프로필의 organizations[].key(사용자 RSA 로 감싼 값)라
    /// 현재는 **이름 복호화가 가능한 것만** 돌려준다(불가하면 이름을 비워 표시).
    public func organizations() async throws -> [VaultOrganization] {
        let (client, token, _) = try requireUnlocked()
        let sync = try await client.sync(token: token)
        return (sync.profile.organizations ?? []).compactMap { org in
            guard let id = org.id else { return nil }
            return VaultOrganization(
                id: id,
                name: org.name ?? "(이름 없음)",
                enabled: org.enabled ?? true
            )
        }
    }

    /// 조직 컬렉션 목록(이름은 조직 키가 필요해 복호화 실패 시 원문 유지).
    public func collections() async throws -> [VaultCollection] {
        let (client, token, userKey) = try requireUnlocked()
        let sync = try await client.sync(token: token)
        return (sync.collections ?? []).compactMap { dto in
            guard let id = dto.id, let organizationId = dto.organizationId else { return nil }
            let name = dto.name.flatMap { try? BitwardenCrypto.decryptString($0, key: userKey) }
                ?? "(조직 키 필요)"
            return VaultCollection(id: id, name: name, organizationId: organizationId)
        }
    }

    /// 항목을 조직 컬렉션에 배정(개인 항목이면 조직으로 이동).
    public func setCollections(itemID: String, organizationID: String?, collectionIDs: [String]) async throws {
        let items = try await syncItems()
        guard var item = items.first(where: { $0.id == itemID }) else { throw SessionError.notUnlocked }
        item.organizationId = organizationID
        item.collectionIds = collectionIDs
        try await save(item)
    }

    /// 폴더 생성. 같은 이름이 이미 있으면 그것을 돌려준다(멱등).
    @discardableResult
    public func createFolder(name: String) async throws -> VaultFolder {
        let (client, token, userKey) = try requireUnlocked()
        let existing = try await syncVault().folders
        if let match = existing.first(where: { $0.name == name }) { return match }
        let encrypted = try BitwardenCrypto.encryptString(name, key: userKey)
        let dto = try await client.createFolder(encryptedName: encrypted, token: token)
        guard let id = dto.id else { throw SessionError.notUnlocked }
        return VaultFolder(id: id, name: name)
    }

    public func renameFolder(id: String, to name: String) async throws {
        let (client, token, userKey) = try requireUnlocked()
        let encrypted = try BitwardenCrypto.encryptString(name, key: userKey)
        _ = try await client.updateFolder(id: id, encryptedName: encrypted, token: token)
    }

    /// 폴더 삭제 — 소속 항목은 미분류로 남는다(항목이 사라지지 않는다).
    public func deleteFolder(id: String) async throws {
        let (client, token, _) = try requireUnlocked()
        try await client.deleteFolder(id: id, token: token)
    }

    /// 항목을 폴더로 옮긴다(nil = 미분류).
    public func moveItem(id: String, toFolder folderID: String?) async throws {
        let items = try await syncItems()
        guard var item = items.first(where: { $0.id == id }) else {
            throw SessionError.notUnlocked
        }
        item.folderId = folderID
        try await save(item)
    }

    /// 태그 이름 일괄 변경 — 해당 태그를 가진 모든 활성 항목의 `태그` 필드를 고친다.
    /// 반환: 저장한 항목 수.
    @discardableResult
    public func renameTag(from old: String, to new: String) async throws -> Int {
        let oldTag = old.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTag = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldTag.isEmpty, !newTag.isEmpty, oldTag != newTag else { return 0 }
        let items = try await syncItems().filter { !$0.deleted }
        var changed = 0
        for var item in items {
            guard item.renameTag(from: oldTag, to: newTag) else { continue }
            try await save(item)
            changed += 1
        }
        return changed
    }

    /// 휴지통 항목 복원.
    public func restore(id: String) async throws {
        let (client, token, _) = try requireUnlocked()
        try await client.restoreCipher(id: id, token: token)
    }

    /// 휴지통에서 영구 삭제.
    public func purge(id: String) async throws {
        let (client, token, _) = try requireUnlocked()
        try await client.purgeCipher(id: id, token: token)
    }

    public func delete(id: String) async throws {
        let (client, token, _) = try requireUnlocked()
        try await client.deleteCipher(id: id, token: token)
    }
}
