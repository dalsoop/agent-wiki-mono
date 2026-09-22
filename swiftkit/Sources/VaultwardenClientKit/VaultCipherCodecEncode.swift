import Foundation

extension VaultCipherCodec {
    static func encode(
        _ item: VaultItem,
        uris: [String],
        key: BitwardenCrypto.SymmetricKeySet
    ) throws -> CipherDTO {
        var dto = CipherDTO(type: item.type == 0 ? 1 : item.type)
        dto.id = item.id.isEmpty ? nil : item.id
        dto.key = item.cipherKey
        dto.folderId = item.folderId
        dto.favorite = item.favorite
        dto.name = try BitwardenCrypto.encryptString(item.name, key: key)
        dto.notes = item.notes.isEmpty ? nil : try BitwardenCrypto.encryptString(item.notes, key: key)
        var login = LoginDTO()
        login.username = item.username.isEmpty ? nil : try BitwardenCrypto.encryptString(item.username, key: key)
        login.password = item.password.isEmpty ? nil : try BitwardenCrypto.encryptString(item.password, key: key)
        login.uris = uris.isEmpty ? nil : (try uris.map { UriDTO(uri: try BitwardenCrypto.encryptString($0, key: key)) })
        login.totp = item.totp.flatMap { $0.isEmpty ? nil : try? BitwardenCrypto.encryptString($0, key: key) }
        dto.fields = item.fields.isEmpty ? nil : (try item.fields.map {
            FieldDTO(
                type: $0.hidden ? 1 : 0,
                name: try BitwardenCrypto.encryptString($0.name, key: key),
                value: try BitwardenCrypto.encryptString($0.value, key: key)
            )
        })
        try attachTypedPayload(item, login: login, to: &dto, key: key)
        dto.organizationId = item.organizationId
        dto.collectionIds = item.collectionIds.isEmpty ? nil : item.collectionIds
        return dto
    }

    static func attachTypedPayload(
        _ item: VaultItem,
        login: LoginDTO,
        to dto: inout CipherDTO,
        key: BitwardenCrypto.SymmetricKeySet
    ) throws {
        func enc(_ value: String) throws -> String? {
            value.isEmpty ? nil : try BitwardenCrypto.encryptString(value, key: key)
        }
        switch dto.type {
        case 2:
            dto.secureNote = SecureNoteDTO(type: 0)
        case 3:
            let card = item.card ?? VaultCard()
            dto.card = CardDTO(
                cardholderName: try enc(card.cardholderName),
                brand: try enc(card.brand),
                number: try enc(card.number),
                expMonth: try enc(card.expMonth),
                expYear: try enc(card.expYear),
                code: try enc(card.code)
            )
        case 4:
            let identity = item.identity ?? VaultIdentity()
            dto.identity = IdentityDTO(
                person: .init(
                    title: try enc(identity.title),
                    firstName: try enc(identity.firstName),
                    lastName: try enc(identity.lastName),
                    company: try enc(identity.company)
                ),
                contact: .init(
                    email: try enc(identity.email),
                    phone: try enc(identity.phone),
                    address1: try enc(identity.address1),
                    city: try enc(identity.city)
                ),
                documents: .init(
                    state: try enc(identity.state),
                    postalCode: try enc(identity.postalCode),
                    country: try enc(identity.country),
                    ssn: try enc(identity.ssn),
                    licenseNumber: try enc(identity.licenseNumber),
                    passportNumber: try enc(identity.passportNumber)
                )
            )
        default:
            dto.login = login
        }
    }
}
