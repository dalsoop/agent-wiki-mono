import Foundation

// MARK: - API DTO (Bitwarden JSON — camelCase/PascalCase 겸용 파싱)

public struct PreloginResponse: Decodable, Sendable {
    public let kdf: Int
    public let kdfIterations: Int
    enum CodingKeys: String, CodingKey {
        case Kdf, KdfIterations, kdf, kdfIterations
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kdf = try c.decodeIfPresent(Int.self, forKey: .Kdf) ?? c.decode(Int.self, forKey: .kdf)
        kdfIterations = try c.decodeIfPresent(Int.self, forKey: .KdfIterations)
            ?? c.decode(Int.self, forKey: .kdfIterations)
    }
}

public struct TokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?
    public let key: String?          // 사용자 대칭키 EncString (stretched master key로 암호화)
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case Key, key
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        expiresIn = try c.decodeIfPresent(Int.self, forKey: .expiresIn)
        key = try c.decodeIfPresent(String.self, forKey: .Key)
            ?? c.decodeIfPresent(String.self, forKey: .key)
    }
}

/// /api/sync 응답 중 사용하는 부분만.
public struct SyncResponse: Decodable, Sendable {
    public let profile: ProfileDTO
    public let ciphers: [CipherDTO]
    public let folders: [FolderDTO]
    public let collections: [CollectionDTO]?
    enum CodingKeys: String, CodingKey {
        case Profile, Ciphers, Folders, Collections, profile, ciphers, folders, collections
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile = try c.decodeIfPresent(ProfileDTO.self, forKey: .Profile)
            ?? c.decode(ProfileDTO.self, forKey: .profile)
        ciphers = try c.decodeIfPresent([CipherDTO].self, forKey: .Ciphers)
            ?? c.decode([CipherDTO].self, forKey: .ciphers)
        folders = (try? c.decodeIfPresent([FolderDTO].self, forKey: .Folders))
            ?? (try? c.decodeIfPresent([FolderDTO].self, forKey: .folders)) ?? []
        collections = (try? c.decodeIfPresent([CollectionDTO].self, forKey: .Collections))
            ?? (try? c.decodeIfPresent([CollectionDTO].self, forKey: .collections)) ?? []
    }
}

public struct FolderDTO: Decodable, Sendable {
    public let id: String?
    public let name: String?          // EncString
    enum CodingKeys: String, CodingKey { case Id, Name, id, name }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? c.decodeIfPresent(String.self, forKey: .Id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? c.decodeIfPresent(String.self, forKey: .Name)
    }
}

/// 조직 요약(프로필에 실려 온다).
public struct OrganizationDTO: Decodable, Sendable {
    public let id: String?
    public let name: String?
    public let enabled: Bool?
    /// 사용자 RSA 로 감싼 조직 대칭키.
    public let key: String?
    enum CodingKeys: String, CodingKey {
        case Id, Name, Enabled, Key, id, name, enabled, key
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? c.decodeIfPresent(String.self, forKey: .Id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? c.decodeIfPresent(String.self, forKey: .Name)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? c.decodeIfPresent(Bool.self, forKey: .Enabled)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? c.decodeIfPresent(String.self, forKey: .Key)
    }
}

/// 조직 컬렉션(조직 항목의 분류축 — 항목당 여러 개 가능).
public struct CollectionDTO: Decodable, Sendable {
    public let id: String?
    public let name: String?          // EncString(조직 키)
    public let organizationId: String?
    enum CodingKeys: String, CodingKey {
        case Id, Name, OrganizationId, id, name, organizationId
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? c.decodeIfPresent(String.self, forKey: .Id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? c.decodeIfPresent(String.self, forKey: .Name)
        organizationId = try c.decodeIfPresent(String.self, forKey: .organizationId)
            ?? c.decodeIfPresent(String.self, forKey: .OrganizationId)
    }
}

/// 표시용 조직.
public struct VaultOrganization: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let enabled: Bool
    public init(id: String, name: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.enabled = enabled
    }
}

/// 표시용 컬렉션.
public struct VaultCollection: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let organizationId: String
    public init(id: String, name: String, organizationId: String) {
        self.id = id
        self.name = name
        self.organizationId = organizationId
    }
}

public struct ProfileDTO: Decodable, Sendable {
    public let email: String?
    public let key: String?
    public let organizations: [OrganizationDTO]?
    enum CodingKeys: String, CodingKey {
        case Email, Key, Organizations, email, key, organizations
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        organizations = try c.decodeIfPresent([OrganizationDTO].self, forKey: .organizations)
            ?? c.decodeIfPresent([OrganizationDTO].self, forKey: .Organizations)
        email = try c.decodeIfPresent(String.self, forKey: .Email)
            ?? c.decodeIfPresent(String.self, forKey: .email)
        key = try c.decodeIfPresent(String.self, forKey: .Key)
            ?? c.decodeIfPresent(String.self, forKey: .key)
    }
}

/// cipher 항목. 읽기(camel/Pascal 겸용)·쓰기(camelCase).
public struct CipherDTO: Codable, Sendable {
    public var id: String?
    public var type: Int              // 1 = login
    public var name: String?          // EncString
    public var notes: String?         // EncString
    public var login: LoginDTO?
    public var secureNote: SecureNoteDTO?   // type 2
    public var favorite: Bool?
    public var deletedDate: String?
    /// 개별 cipher key(EncString, 2023+ 형식) — 있으면 필드들이 이 키로 암호화돼 있다.
    public var key: String?
    public var folderId: String?
    public var fields: [FieldDTO]?
    public var card: CardDTO?
    public var identity: IdentityDTO?
    /// 조직 소유 항목이면 조직 id, 개인 항목이면 nil.
    public var organizationId: String?
    /// 조직 항목이 속한 컬렉션 id 목록.
    public var collectionIds: [String]?
    /// 첨부파일 메타(서버 제공, 읽기 전용 — 업로드는 전용 엔드포인트).
    public var attachments: [AttachmentDTO]?

    public init(id: String? = nil, type: Int = 1, name: String? = nil,
                notes: String? = nil, login: LoginDTO? = nil,
                secureNote: SecureNoteDTO? = nil,
                favorite: Bool? = nil, deletedDate: String? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.notes = notes
        self.login = login
        self.secureNote = secureNote
        self.favorite = favorite
        self.deletedDate = deletedDate
    }

    // 서버가 대문자 키(`Name`)와 소문자 키(`name`)를 섞어 쓰기 때문에 인코더·디코더를 손으로 쓴다.
    // **필드를 추가하면 CodingKeys·init(from:)·encode(to:) 세 곳을 같이 고쳐야 한다** —
    // 프로퍼티만 늘리면 컴파일은 되고 값만 조용히 사라진다. 실제로 identity·organizationId·
    // collectionIds 가 그렇게 빠져 있었다: 신원 항목은 늘 빈 값으로 읽혔고(저장하면 소실),
    // 조직·컬렉션 배정은 저장돼도 서버에 안 갔다.
    enum CodingKeys: String, CodingKey {
        case id, type, name, notes, login, secureNote, favorite, deletedDate, key, folderId, fields, card
        case identity, organizationId, collectionIds, attachments
        case Id, Name, Notes, Login, SecureNote, Favorite, DeletedDate, Key, FolderId, Fields, Card
        case Identity, OrganizationId, CollectionIds, Attachments
        case TypeUpper = "Type"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? c.decodeIfPresent(String.self, forKey: .Id)
        type = try c.decodeIfPresent(Int.self, forKey: .type) ?? c.decodeIfPresent(Int.self, forKey: .TypeUpper) ?? 0
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? c.decodeIfPresent(String.self, forKey: .Name)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? c.decodeIfPresent(String.self, forKey: .Notes)
        login = try c.decodeIfPresent(LoginDTO.self, forKey: .login) ?? c.decodeIfPresent(LoginDTO.self, forKey: .Login)
        secureNote = try c.decodeIfPresent(SecureNoteDTO.self, forKey: .secureNote) ?? c.decodeIfPresent(SecureNoteDTO.self, forKey: .SecureNote)
        favorite = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? c.decodeIfPresent(Bool.self, forKey: .Favorite)
        deletedDate = try c.decodeIfPresent(String.self, forKey: .deletedDate) ?? c.decodeIfPresent(String.self, forKey: .DeletedDate)
        key = try c.decodeIfPresent(String.self, forKey: .key) ?? c.decodeIfPresent(String.self, forKey: .Key)
        folderId = try c.decodeIfPresent(String.self, forKey: .folderId) ?? c.decodeIfPresent(String.self, forKey: .FolderId)
        fields = try c.decodeIfPresent([FieldDTO].self, forKey: .fields) ?? c.decodeIfPresent([FieldDTO].self, forKey: .Fields)
        card = try c.decodeIfPresent(CardDTO.self, forKey: .card) ?? c.decodeIfPresent(CardDTO.self, forKey: .Card)
        identity = try c.decodeIfPresent(IdentityDTO.self, forKey: .identity)
            ?? c.decodeIfPresent(IdentityDTO.self, forKey: .Identity)
        organizationId = try c.decodeIfPresent(String.self, forKey: .organizationId)
            ?? c.decodeIfPresent(String.self, forKey: .OrganizationId)
        collectionIds = try c.decodeIfPresent([String].self, forKey: .collectionIds)
            ?? c.decodeIfPresent([String].self, forKey: .CollectionIds)
        attachments = try c.decodeIfPresent([AttachmentDTO].self, forKey: .attachments)
            ?? c.decodeIfPresent([AttachmentDTO].self, forKey: .Attachments)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encodeIfPresent(login, forKey: .login)
        try c.encodeIfPresent(secureNote, forKey: .secureNote)
        try c.encode(favorite ?? false, forKey: .favorite)
        try c.encodeIfPresent(key, forKey: .key)
        try c.encodeIfPresent(folderId, forKey: .folderId)
        try c.encodeIfPresent(fields, forKey: .fields)
        try c.encodeIfPresent(card, forKey: .card)
        try c.encodeIfPresent(identity, forKey: .identity)
        try c.encodeIfPresent(organizationId, forKey: .organizationId)
        try c.encodeIfPresent(collectionIds, forKey: .collectionIds)
        // attachments 는 서버가 주는 읽기 전용 메타라 실어 보내지 않는다(업로드는 전용 엔드포인트).
    }
}

/// 커스텀 필드. type: 0 텍스트 · 1 히든 · 2 불리언 · 3 링크드.
public struct FieldDTO: Codable, Sendable {
    public var type: Int?
    public var name: String?          // EncString
    public var value: String?         // EncString
    enum CodingKeys: String, CodingKey { case type, name, value, Name, Value
        case TypeUpper = "Type" }
    public init(type: Int? = nil, name: String? = nil, value: String? = nil) {
        self.type = type; self.name = name; self.value = value
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(Int.self, forKey: .type) ?? c.decodeIfPresent(Int.self, forKey: .TypeUpper)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? c.decodeIfPresent(String.self, forKey: .Name)
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? c.decodeIfPresent(String.self, forKey: .Value)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(type, forKey: .type)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(value, forKey: .value)
    }
}

/// 카드 항목 필드(전부 EncString).
/// 신원(type 4) — 여권·주민번호 등 개인 식별 정보.
public struct IdentityDTO: Codable, Sendable {
    public var title: String?
    public var firstName: String?
    public var lastName: String?
    public var company: String?
    public var email: String?
    public var phone: String?
    public var address1: String?
    public var city: String?
    public var state: String?
    public var postalCode: String?
    public var country: String?
    public var ssn: String?
    public var licenseNumber: String?
    public var passportNumber: String?

    public struct Person: Sendable {
        public var title: String?
        public var firstName: String?
        public var lastName: String?
        public var company: String?

        public init(
            title: String? = nil,
            firstName: String? = nil,
            lastName: String? = nil,
            company: String? = nil
        ) {
            self.title = title
            self.firstName = firstName
            self.lastName = lastName
            self.company = company
        }
    }

    public struct Contact: Sendable {
        public var email: String?
        public var phone: String?
        public var address1: String?
        public var city: String?

        public init(
            email: String? = nil,
            phone: String? = nil,
            address1: String? = nil,
            city: String? = nil
        ) {
            self.email = email
            self.phone = phone
            self.address1 = address1
            self.city = city
        }
    }

    public struct Documents: Sendable {
        public var state: String?
        public var postalCode: String?
        public var country: String?
        public var ssn: String?
        public var licenseNumber: String?
        public var passportNumber: String?

        public init(
            state: String? = nil,
            postalCode: String? = nil,
            country: String? = nil,
            ssn: String? = nil,
            licenseNumber: String? = nil,
            passportNumber: String? = nil
        ) {
            self.state = state
            self.postalCode = postalCode
            self.country = country
            self.ssn = ssn
            self.licenseNumber = licenseNumber
            self.passportNumber = passportNumber
        }
    }

    public init(
        person: Person = Person(),
        contact: Contact = Contact(),
        documents: Documents = Documents()
    ) {
        self.title = person.title
        self.firstName = person.firstName
        self.lastName = person.lastName
        self.company = person.company
        self.email = contact.email
        self.phone = contact.phone
        self.address1 = contact.address1
        self.city = contact.city
        self.state = documents.state
        self.postalCode = documents.postalCode
        self.country = documents.country
        self.ssn = documents.ssn
        self.licenseNumber = documents.licenseNumber
        self.passportNumber = documents.passportNumber
    }

    /// 서버가 camelCase(`firstName`)와 PascalCase(`FirstName`)를 섞어 준다. 14개 필드마다
    /// 키를 두 벌 적는 대신 첫 글자만 내려서 한 번에 맞춘다(CardDTO 는 두 벌 적는 방식 —
    /// 필드가 적어서 감당되지만 여기서는 늘어날 때마다 빠뜨릴 자리가 두 배가 된다).
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: String?].self)
        var byLowerCamel: [String: String] = [:]
        for (key, value) in raw {
            guard let value else { continue }
            byLowerCamel[key.prefix(1).lowercased() + key.dropFirst()] = value
        }
        title = byLowerCamel["title"]
        firstName = byLowerCamel["firstName"]
        lastName = byLowerCamel["lastName"]
        company = byLowerCamel["company"]
        email = byLowerCamel["email"]
        phone = byLowerCamel["phone"]
        address1 = byLowerCamel["address1"]
        city = byLowerCamel["city"]
        state = byLowerCamel["state"]
        postalCode = byLowerCamel["postalCode"]
        country = byLowerCamel["country"]
        ssn = byLowerCamel["ssn"]
        licenseNumber = byLowerCamel["licenseNumber"]
        passportNumber = byLowerCamel["passportNumber"]
    }
}

public struct CardDTO: Codable, Sendable {
    public var cardholderName: String?
    public var brand: String?
    public var number: String?
    public var expMonth: String?
    public var expYear: String?
    public var code: String?

    public init(
        cardholderName: String? = nil, brand: String? = nil, number: String? = nil,
        expMonth: String? = nil, expYear: String? = nil, code: String? = nil
    ) {
        self.cardholderName = cardholderName
        self.brand = brand
        self.number = number
        self.expMonth = expMonth
        self.expYear = expYear
        self.code = code
    }

    enum CodingKeys: String, CodingKey {
        case cardholderName, brand, number, expMonth, expYear, code
        case CardholderName, Brand, Number, ExpMonth, ExpYear, Code
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cardholderName = try c.decodeIfPresent(String.self, forKey: .cardholderName) ?? c.decodeIfPresent(String.self, forKey: .CardholderName)
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? c.decodeIfPresent(String.self, forKey: .Brand)
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? c.decodeIfPresent(String.self, forKey: .Number)
        expMonth = try c.decodeIfPresent(String.self, forKey: .expMonth) ?? c.decodeIfPresent(String.self, forKey: .ExpMonth)
        expYear = try c.decodeIfPresent(String.self, forKey: .expYear) ?? c.decodeIfPresent(String.self, forKey: .ExpYear)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? c.decodeIfPresent(String.self, forKey: .Code)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(cardholderName, forKey: .cardholderName)
        try c.encodeIfPresent(brand, forKey: .brand)
        try c.encodeIfPresent(number, forKey: .number)
        try c.encodeIfPresent(expMonth, forKey: .expMonth)
        try c.encodeIfPresent(expYear, forKey: .expYear)
        try c.encodeIfPresent(code, forKey: .code)
    }
}

public struct LoginDTO: Codable, Sendable {
    public var username: String?      // EncString
    public var password: String?      // EncString
    public var uris: [UriDTO]?
    public var totp: String?          // EncString (otpauth:// 또는 base32 시드)

    public init(username: String? = nil, password: String? = nil, uris: [UriDTO]? = nil, totp: String? = nil) {
        self.username = username
        self.password = password
        self.uris = uris
        self.totp = totp
    }

    enum CodingKeys: String, CodingKey { case username, password, uris, totp, Username, Password, Uris, Totp }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? c.decodeIfPresent(String.self, forKey: .Username)
        password = try c.decodeIfPresent(String.self, forKey: .password) ?? c.decodeIfPresent(String.self, forKey: .Password)
        uris = try c.decodeIfPresent([UriDTO].self, forKey: .uris) ?? c.decodeIfPresent([UriDTO].self, forKey: .Uris)
        totp = try c.decodeIfPresent(String.self, forKey: .totp) ?? c.decodeIfPresent(String.self, forKey: .Totp)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(password, forKey: .password)
        try c.encodeIfPresent(uris, forKey: .uris)
        try c.encodeIfPresent(totp, forKey: .totp)
    }
}

public struct SecureNoteDTO: Codable, Sendable {
    public var type: Int   // 0 = generic
    public init(type: Int = 0) { self.type = type }
    enum CodingKeys: String, CodingKey { case type; case TypeUpper = "Type" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(Int.self, forKey: .type) ?? c.decodeIfPresent(Int.self, forKey: .TypeUpper) ?? 0
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
    }
}

public struct UriDTO: Codable, Sendable {
    public var uri: String?           // EncString
    public init(uri: String?) { self.uri = uri }
    enum CodingKeys: String, CodingKey { case uri, Uri }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uri = try c.decodeIfPresent(String.self, forKey: .uri) ?? c.decodeIfPresent(String.self, forKey: .Uri)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(uri, forKey: .uri)
    }
}

// MARK: - 복호화된 도메인 모델

/// 복호화된 커스텀 필드.
public struct VaultField: Sendable, Equatable {
    public var name: String
    public var value: String
    /// type 1(hidden) — UI 는 마스킹 후 보기/복사 제공.
    public var hidden: Bool
    public init(name: String, value: String, hidden: Bool) {
        self.name = name; self.value = value; self.hidden = hidden
    }
}

/// 복호화된 카드 요약.
/// 신원 항목(복호화된 표시용).
public struct VaultIdentity: Sendable, Equatable {
    public var title: String
    public var firstName: String
    public var lastName: String
    public var company: String
    public var email: String
    public var phone: String
    public var address1: String
    public var city: String
    public var state: String
    public var postalCode: String
    public var country: String
    public var ssn: String
    public var licenseNumber: String
    public var passportNumber: String

    public struct Person: Sendable, Equatable {
        public var title: String
        public var firstName: String
        public var lastName: String
        public var company: String

        public init(
            title: String = "",
            firstName: String = "",
            lastName: String = "",
            company: String = ""
        ) {
            self.title = title
            self.firstName = firstName
            self.lastName = lastName
            self.company = company
        }
    }

    public struct Contact: Sendable, Equatable {
        public var email: String
        public var phone: String
        public var address1: String
        public var city: String

        public init(
            email: String = "",
            phone: String = "",
            address1: String = "",
            city: String = ""
        ) {
            self.email = email
            self.phone = phone
            self.address1 = address1
            self.city = city
        }
    }

    public struct Documents: Sendable, Equatable {
        public var state: String
        public var postalCode: String
        public var country: String
        public var ssn: String
        public var licenseNumber: String
        public var passportNumber: String

        public init(
            state: String = "",
            postalCode: String = "",
            country: String = "",
            ssn: String = "",
            licenseNumber: String = "",
            passportNumber: String = ""
        ) {
            self.state = state
            self.postalCode = postalCode
            self.country = country
            self.ssn = ssn
            self.licenseNumber = licenseNumber
            self.passportNumber = passportNumber
        }
    }

    public init(
        person: Person = Person(),
        contact: Contact = Contact(),
        documents: Documents = Documents()
    ) {
        self.title = person.title
        self.firstName = person.firstName
        self.lastName = person.lastName
        self.company = person.company
        self.email = contact.email
        self.phone = contact.phone
        self.address1 = contact.address1
        self.city = contact.city
        self.state = documents.state
        self.postalCode = documents.postalCode
        self.country = documents.country
        self.ssn = documents.ssn
        self.licenseNumber = documents.licenseNumber
        self.passportNumber = documents.passportNumber
    }

    public var isEmpty: Bool {
        [title, firstName, lastName, company, email, phone, address1, city,
         state, postalCode, country, ssn, licenseNumber, passportNumber].allSatisfy(\.isEmpty)
    }
}

public struct VaultCard: Sendable, Equatable {
    public var cardholderName: String
    public var brand: String
    public var number: String
    public var expMonth: String
    public var expYear: String
    public var code: String
    public init(cardholderName: String = "", brand: String = "", number: String = "",
                expMonth: String = "", expYear: String = "", code: String = "") {
        self.cardholderName = cardholderName; self.brand = brand; self.number = number
        self.expMonth = expMonth; self.expYear = expYear; self.code = code
    }
}

public struct VaultFolder: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

/// 이 킷이 **온전히 왕복시킬 수 있는** cipher 유형. 여기 없는 유형은 저장하지 않는다 —
/// 모르는 하위 오브젝트(예: SSH 키의 privateKey)를 안 실어 보내면 저장하는 순간 지워지고,
/// 비밀번호와 달리 개인키는 되찾을 방법이 없다. 새 유형을 지원하려면 모델·인코더·에디터를
/// 갖춘 뒤 여기에 더한다.
public enum VaultCipherType {
    public static let editable: Set<Int> = [1, 2, 3, 4]

    /// 사람에게 보여줄 이름(모르는 유형도 번호로 말한다).
    public static func label(_ type: Int) -> String {
        switch type {
        case 1: "로그인"
        case 2: "보안 메모"
        case 3: "카드"
        case 4: "신원"
        case 5: "SSH 키"
        default: "유형 \(type)"
        }
    }
}

public struct VaultItem: Sendable, Equatable, Identifiable {
    public var id: String
    /// cipher type: 1 로그인 · 2 노트 · 3 카드 · 4 신원 (그 외는 원시값 유지)
    public var type: Int
    public var name: String
    public var username: String
    public var password: String
    /// 첫 URI(호환 필드). 읽기·쓰기는 `loginURIs`.
    public var uri: String
    /// cipher `login.uris` 저장용 배열. 읽기·쓰기는 `loginURIs`.
    public var uris: [String]
    public var notes: String
    public var favorite: Bool
    public var folderId: String?
    public var totp: String?
    public var fields: [VaultField]
    public var card: VaultCard?
    public var identity: VaultIdentity?
    /// 조직 소유면 조직 id(개인 금고 항목은 nil).
    public var organizationId: String?
    /// 조직 항목이 속한 컬렉션들.
    public var collectionIds: [String]
    public var deleted: Bool
    /// 개별 cipher key EncString(있는 항목만). 저장 시 그대로 유지해 재암호화 호환을 지킨다.
    public var cipherKey: String?

    public struct Core: Sendable, Equatable {
        public var id: String
        public var type: Int
        public var name: String
        public var notes: String
        public var favorite: Bool
        public var folderId: String?
        public var deleted: Bool
        public var cipherKey: String?

        public init(
            id: String = "",
            type: Int = 1,
            name: String = "",
            notes: String = "",
            favorite: Bool = false,
            folderId: String? = nil,
            deleted: Bool = false,
            cipherKey: String? = nil
        ) {
            self.id = id
            self.type = type
            self.name = name
            self.notes = notes
            self.favorite = favorite
            self.folderId = folderId
            self.deleted = deleted
            self.cipherKey = cipherKey
        }
    }

    public struct Login: Sendable, Equatable {
        public var username: String
        public var password: String
        public var uri: String
        public var uris: [String]
        public var totp: String?

        public init(
            username: String = "",
            password: String = "",
            uri: String = "",
            uris: [String] = [],
            totp: String? = nil
        ) {
            self.username = username
            self.password = password
            self.uri = uri
            self.uris = uris
            self.totp = totp
        }
    }

    public struct Extras: Sendable, Equatable {
        public var fields: [VaultField]
        public var card: VaultCard?
        public var identity: VaultIdentity?
        public var organizationId: String?
        public var collectionIds: [String]

        public init(
            fields: [VaultField] = [],
            card: VaultCard? = nil,
            identity: VaultIdentity? = nil,
            organizationId: String? = nil,
            collectionIds: [String] = []
        ) {
            self.fields = fields
            self.card = card
            self.identity = identity
            self.organizationId = organizationId
            self.collectionIds = collectionIds
        }
    }

    public init(
        core: Core,
        login: Login = Login(),
        extras: Extras = Extras()
    ) {
        self.id = core.id
        self.type = core.type
        self.name = core.name
        self.username = login.username
        self.password = login.password
        self.uri = login.uri
        self.uris = login.uris
        self.notes = core.notes
        self.favorite = core.favorite
        self.folderId = core.folderId
        self.totp = login.totp
        self.fields = extras.fields
        self.card = extras.card
        self.identity = extras.identity
        self.organizationId = extras.organizationId
        self.collectionIds = extras.collectionIds
        self.deleted = core.deleted
        self.cipherKey = core.cipherKey
    }

    public init(
        id: String = "",
        type: Int = 1,
        name: String = "",
        username: String = "",
        password: String = "",
        uri: String = "",
        uris: [String] = [],
        notes: String = ""
    ) {
        self.init(
            core: Core(id: id, type: type, name: name, notes: notes),
            login: Login(username: username, password: password, uri: uri, uris: uris)
        )
    }

    /// 로그인 웹 주소의 **항목 안 정본**. cipher `login.uris` 와 같다.
    /// `uri` 는 첫 주소 호환 필드일 뿐, 따로 쓰지 않는다.
    public var loginURIs: [String] {
        get {
            let raw = uris.isEmpty ? (uri.isEmpty ? [] : [uri]) : uris
            return raw.filter { !Self.isBlankLoginURI($0) }
        }
        set {
            let cleaned = newValue.filter { !Self.isBlankLoginURI($0) }
            uris = cleaned
            uri = cleaned.first ?? ""
        }
    }

    public var isLogin: Bool { type == 0 || type == 1 }

    /// 로그인인데 웹 주소가 없다 — 새 항목 저장 거부·수리 파이프라인 대상.
    public var needsLoginURI: Bool { isLogin && loginURIs.isEmpty }

    public static func isBlankLoginURI(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        return lower == "https://" || lower == "http://" || lower == "https" || lower == "http"
    }

    /// 태그 필드 이름(커스텀 필드 규약) — 공식 클라이언트에서도 일반 필드로 보인다.
    public static let tagFieldName = "태그"

    /// 이 항목의 태그들(쉼표 구분 커스텀 필드).
    public var tags: [String] {
        get {
            guard let field = fields.first(where: { $0.name == Self.tagFieldName }) else { return [] }
            return field.value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set {
            let joined = newValue
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if let index = fields.firstIndex(where: { $0.name == Self.tagFieldName }) {
                if joined.isEmpty {
                    fields.remove(at: index)
                } else {
                    fields[index].value = joined
                }
            } else if !joined.isEmpty {
                fields.append(VaultField(name: Self.tagFieldName, value: joined, hidden: false))
            }
        }
    }

    /// 태그 이름을 이 항목 안에서 바꾼다. `new` 가 이미 있으면 중복을 합친다.
    /// 옛 태그가 없으면 false, 바뀌면 true.
    @discardableResult
    public mutating func renameTag(from old: String, to new: String) -> Bool {
        let oldTag = old.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTag = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldTag.isEmpty, !newTag.isEmpty, oldTag != newTag else { return false }
        let current = tags
        guard current.contains(oldTag) else { return false }
        var seen = Set<String>()
        var next: [String] = []
        for tag in current {
            let replaced = tag == oldTag ? newTag : tag
            if seen.insert(replaced).inserted {
                next.append(replaced)
            }
        }
        guard next != current else { return false }
        tags = next
        return true
    }

    public func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(q)
            || username.localizedCaseInsensitiveContains(q)
            || notes.localizedCaseInsensitiveContains(q)
            || loginURIs.contains { $0.localizedCaseInsensitiveContains(q) }
            || tags.contains { $0.localizedCaseInsensitiveContains(q) }
            || fields.contains { $0.name.localizedCaseInsensitiveContains(q)
                || (!$0.hidden && $0.value.localizedCaseInsensitiveContains(q)) }
    }

    /// 볼트 항목의 URI 호스트와 정확히 같거나 그 하위 도메인인 로그인 요청만 허용한다.
    /// 단순 문자열 suffix가 아니라 점 경계를 포함해 `evilnaver.com` 같은 유사 도메인을 거부한다.
    public func matchesLoginHost(_ requestedHost: String) -> Bool {
        guard let requestHost = Self.normalizedHost(from: requestedHost) else { return false }
        for raw in loginURIs {
            guard let itemHost = Self.normalizedHost(from: raw) else { continue }
            if requestHost == itemHost || requestHost.hasSuffix(".\(itemHost)") {
                return true
            }
        }
        return false
    }

    private static func normalizedHost(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URLComponents(string: candidate)?.host?
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased(),
            !host.isEmpty else {
            return nil
        }
        return host
    }
}
