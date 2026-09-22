import Foundation

enum VaultCipherCodec {
    static func effectiveKey(cipherKey: String?, userKey: BitwardenCrypto.SymmetricKeySet)
        -> BitwardenCrypto.SymmetricKeySet {
        guard let ck = cipherKey,
              let raw = try? BitwardenCrypto.decrypt(BitwardenCrypto.EncString(parse: ck), key: userKey),
              let set = BitwardenCrypto.SymmetricKeySet(raw: raw)
        else { return userKey }
        return set
    }

    static func decrypt(_ dto: CipherDTO, userKey: BitwardenCrypto.SymmetricKeySet) -> VaultItem? {
        guard let id = dto.id else { return nil }
        let fieldKey = effectiveKey(cipherKey: dto.key, userKey: userKey)
        func dec(_ s: String?) -> String {
            guard let s, !s.isEmpty else { return "" }
            return (try? BitwardenCrypto.decryptString(s, key: fieldKey)) ?? "(복호화 실패)"
        }
        let uris = (dto.login?.uris ?? []).compactMap { u -> String? in
            let v = dec(u.uri); return v.isEmpty ? nil : v
        }
        let fields = (dto.fields ?? []).map { f in
            VaultField(name: dec(f.name), value: dec(f.value), hidden: f.type == 1)
        }
        let identity = dto.identity.map { idn in
            VaultIdentity(
                person: .init(
                    title: dec(idn.title),
                    firstName: dec(idn.firstName),
                    lastName: dec(idn.lastName),
                    company: dec(idn.company)
                ),
                contact: .init(
                    email: dec(idn.email),
                    phone: dec(idn.phone),
                    address1: dec(idn.address1),
                    city: dec(idn.city)
                ),
                documents: .init(
                    state: dec(idn.state),
                    postalCode: dec(idn.postalCode),
                    country: dec(idn.country),
                    ssn: dec(idn.ssn),
                    licenseNumber: dec(idn.licenseNumber),
                    passportNumber: dec(idn.passportNumber)
                )
            )
        }
        var card: VaultCard?
        if let c = dto.card {
            card = VaultCard(
                cardholderName: dec(c.cardholderName),
                brand: dec(c.brand),
                number: dec(c.number),
                expMonth: dec(c.expMonth),
                expYear: dec(c.expYear),
                code: dec(c.code)
            )
        }
        let totp = dec(dto.login?.totp)
        return VaultItem(
            core: .init(
                id: id,
                type: dto.type,
                name: dec(dto.name),
                notes: dec(dto.notes),
                favorite: dto.favorite ?? false,
                folderId: dto.folderId,
                deleted: dto.deletedDate != nil,
                cipherKey: dto.key
            ),
            login: .init(
                username: dec(dto.login?.username),
                password: dec(dto.login?.password),
                uri: uris.first ?? "",
                uris: uris,
                totp: totp.isEmpty ? nil : totp
            ),
            extras: .init(
                fields: fields,
                card: card,
                identity: identity,
                organizationId: dto.organizationId,
                collectionIds: dto.collectionIds ?? []
            )
        )
    }
}

