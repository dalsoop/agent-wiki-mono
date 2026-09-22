import Foundation

extension VaultSession {
    public struct SecureNoteRef: Sendable, Equatable {
        public let id: String
        public let name: String
        public init(id: String, name: String) { self.id = id; self.name = name }
    }

    /// 저장된 Secure Note 목록(이름).
    public func listSecureNotes() async throws -> [SecureNoteRef] {
        let (client, token, key) = try requireUnlocked()
        let sync = try await client.sync(token: token)
        return sync.ciphers
            .filter { $0.type == 2 && $0.deletedDate == nil }
            .compactMap { c -> SecureNoteRef? in
                guard let id = c.id, let enc = c.name,
                      let name = try? BitwardenCrypto.decryptString(enc, key: key) else { return nil }
                return SecureNoteRef(id: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// 이름으로 Secure Note 본문(notes) 복호화. 없으면 nil.
    public func secureNoteText(name: String) async throws -> String? {
        let (client, token, key) = try requireUnlocked()
        let sync = try await client.sync(token: token)
        for c in sync.ciphers where c.type == 2 && c.deletedDate == nil {
            guard let enc = c.name,
                  let n = try? BitwardenCrypto.decryptString(enc, key: key),
                  n.caseInsensitiveCompare(name) == .orderedSame else { continue }
            return c.notes.flatMap { try? BitwardenCrypto.decryptString($0, key: key) } ?? ""
        }
        return nil
    }

    /// Secure Note 저장(같은 이름 있으면 갱신, 없으면 생성).
    public func saveSecureNote(name: String, text: String) async throws {
        let (client, token, key) = try requireUnlocked()
        var dto = CipherDTO(type: 2)
        dto.secureNote = SecureNoteDTO(type: 0)
        dto.name = try BitwardenCrypto.encryptString(name, key: key)
        dto.notes = try BitwardenCrypto.encryptString(text, key: key)
        let sync = try await client.sync(token: token)
        let existing = sync.ciphers.first { c in
            c.type == 2 && c.deletedDate == nil
                && (c.name.flatMap { try? BitwardenCrypto.decryptString($0, key: key) })?
                    .caseInsensitiveCompare(name) == .orderedSame
        }
        if let existing, let id = existing.id {
            dto.id = id
            _ = try await client.updateCipher(dto, token: token)
        } else {
            _ = try await client.createCipher(dto, token: token)
        }
    }

    /// 이름으로 Secure Note 삭제. 없으면 false.
    @discardableResult
    public func deleteSecureNote(name: String) async throws -> Bool {
        let refs = try await listSecureNotes()
        guard let ref = refs.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return false
        }
        try await delete(id: ref.id)
        return true
    }
}
