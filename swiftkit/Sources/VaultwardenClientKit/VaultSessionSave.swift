import Foundation

extension VaultSession {
    public func save(_ item: VaultItem) async throws {
        guard VaultCipherType.editable.contains(item.type == 0 ? 1 : item.type) else {
            throw SessionError.unsupportedItemType(item.type)
        }
        let (client, token, userKey) = try requireUnlocked()
        var item = item
        let key = VaultCipherCodec.effectiveKey(cipherKey: item.cipherKey, userKey: userKey)
        var allURIs = item.loginURIs.map { VaultURIPipeline.normalizedURI($0) }
            .filter { !VaultItem.isBlankLoginURI($0) }
        if allURIs.isEmpty, !item.id.isEmpty, item.isLogin {
            do {
                let remote = try await client.getCipher(id: item.id, token: token)
                if let kept = VaultCipherCodec.decrypt(remote, userKey: userKey) {
                    allURIs = VaultURIPipeline.mergedURIs(incoming: allURIs, existing: kept.loginURIs)
                }
            } catch {}
        }
        let cipherType = item.type == 0 ? 1 : item.type
        if item.id.isEmpty, cipherType == 1, allURIs.isEmpty {
            throw SessionError.missingLoginURI
        }
        if cipherType == 1, !allURIs.isEmpty {
            item.loginURIs = allURIs
            item = VaultURIPipeline.applyAdoption(item)
            allURIs = item.loginURIs
        }
        if cipherType == 1 || cipherType == 2 {
            item = VaultPlacement.apply(item)
        }
        let dto = try VaultCipherCodec.encode(item, uris: allURIs, key: key)
        if item.id.isEmpty {
            _ = try await client.createCipher(dto, token: token)
        } else {
            _ = try await client.updateCipher(dto, token: token)
        }
    }
}
