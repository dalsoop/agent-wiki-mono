import Foundation

extension VaultSession {
    /// 항목의 첨부 목록 — 파일명은 항목 키로 복호화해서 돌려준다.
    public func attachments(itemID: String) async throws -> [VaultAttachment] {
        let (client, token, userKey) = try requireUnlocked()
        let sync = try await client.sync(token: token)
        guard let cipher = sync.ciphers.first(where: { $0.id == itemID }) else { return [] }
        let key = VaultCipherCodec.effectiveKey(cipherKey: cipher.key, userKey: userKey)
        return (cipher.attachments ?? []).compactMap { dto in
            guard let id = dto.id else { return nil }
            let name = dto.fileName.flatMap { try? BitwardenCrypto.decryptString($0, key: key) }
                ?? "(이름 복호화 실패)"
            let size = Int(dto.size ?? "0") ?? 0
            return VaultAttachment(
                id: id, fileName: name, size: size,
                sizeName: dto.sizeName ?? VaultAttachmentCrypto.humanSize(size),
                key: dto.key, url: dto.url
            )
        }
    }

    /// 파일 첨부 — 첨부 전용 키를 만들어 본문을 암호화하고, 그 키는 항목 키로 감싼다.
    /// 공식 클라이언트와 같은 형식이라 웹·모바일에서도 그대로 열린다.
    public func attach(fileURL: URL, toItem itemID: String) async throws {
        let (client, token, userKey) = try requireUnlocked()
        let sync = try await client.sync(token: token)
        guard let cipher = sync.ciphers.first(where: { $0.id == itemID }) else {
            throw SessionError.notUnlocked
        }
        let itemKey = VaultCipherCodec.effectiveKey(cipherKey: cipher.key, userKey: userKey)
        let plaintext = try Data(contentsOf: fileURL)
        let attachmentKey = VaultAttachmentCrypto.makeAttachmentKey()
        let payload = try VaultAttachmentCrypto.encrypt(plaintext, key: attachmentKey)
        let encryptedName = try BitwardenCrypto.encryptString(fileURL.lastPathComponent, key: itemKey)
        let wrappedKey = try BitwardenCrypto.encrypt(attachmentKey.raw, key: itemKey).serialized

        let ticket = try await client.requestAttachmentUpload(
            cipherID: itemID, encryptedFileName: encryptedName,
            fileSize: payload.count, encryptedKey: wrappedKey, token: token
        )
        try await client.uploadAttachmentData(
            cipherID: itemID, attachmentID: ticket.attachmentId, encryptedFileName: encryptedName,
            payload: payload, uploadURL: ticket.url, fileUploadType: ticket.fileUploadType, token: token
        )
    }

    /// 첨부 내려받기 — 복호화해 지정 경로에 쓴다.
    public func downloadAttachment(_ attachment: VaultAttachment, fromItem itemID: String, to outputURL: URL) async throws {
        let (client, token, userKey) = try requireUnlocked()
        let sync = try await client.sync(token: token)
        guard let cipher = sync.ciphers.first(where: { $0.id == itemID }) else {
            throw SessionError.notUnlocked
        }
        let itemKey = VaultCipherCodec.effectiveKey(cipherKey: cipher.key, userKey: userKey)
        guard let wrapped = attachment.key,
              let raw = try? BitwardenCrypto.decrypt(BitwardenCrypto.EncString(parse: wrapped), key: itemKey),
              let attachmentKey = BitwardenCrypto.SymmetricKeySet(raw: raw) else {
            throw BitwardenCrypto.CryptoError.invalidEncString
        }
        let urlString: String
        if let direct = attachment.url, !direct.isEmpty {
            urlString = direct
        } else {
            urlString = try await client.attachmentDownloadURL(
                cipherID: itemID, attachmentID: attachment.id, token: token
            )
        }
        guard let downloadURL = URL(string: urlString) else { throw VaultwardenAPI.APIError.badURL }
        let (data, _) = try await URLSession.shared.data(from: downloadURL)
        let plaintext = try VaultAttachmentCrypto.decrypt(data, key: attachmentKey)
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try plaintext.write(to: outputURL, options: .atomic)
    }

    public func deleteAttachment(_ attachmentID: String, fromItem itemID: String) async throws {
        let (client, token, _) = try requireUnlocked()
        try await client.deleteAttachment(cipherID: itemID, attachmentID: attachmentID, token: token)
    }

    /// 이름으로 Secure Note 항목 id 를 찾거나 만들고 id 를 돌려준다(서류 보관함 용도).
    public func ensureSecureNoteID(name: String, notes: String = "") async throws -> String {
        let items = try await syncItems()
        if let existing = items.first(where: { $0.name == name && $0.type == 2 }) {
            return existing.id
        }
        var item = VaultItem(id: "", type: 2, name: name)
        item.notes = notes
        try await save(item)
        let refreshed = try await syncItems()
        guard let created = refreshed.first(where: { $0.name == name && $0.type == 2 }) else {
            throw SessionError.notUnlocked
        }
        return created.id
    }
}
