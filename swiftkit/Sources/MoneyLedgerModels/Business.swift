import Foundation

/// 사업자 등록 정보(사업자등록증 기재사항). 여러 사업자를 가질 수 있어 목록형이다.
public struct BusinessProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// 상호(법인명).
    public var name: String
    /// 사업자등록번호 — 저장은 숫자 10자리(하이픈 제거). 표기는 `BusinessNumber.format`.
    public var registrationNumber: String
    /// 대표자.
    public var representative: String?
    /// 개업일 "yyyy-MM-dd".
    public var openedDate: String?
    /// 업태.
    public var businessType: String?
    /// 종목.
    public var businessItem: String?
    /// 과세 유형(일반과세/간이과세/법인 등 자유 문자열).
    public var taxationType: String?
    public var address: String?
    public var note: String?
    /// Vaultwarden 서류 보관함 항목 id — 사업자등록증·통신판매업 신고증 등 파일이 첨부로 붙는다.
    public var vaultDocsItemID: String?
    public var archived: Bool
    public var createdAt: Date
    public var updatedAt: Date?

    /// Init-only grouping — stored fields stay flat for payload JSON.
    public struct Identity: Sendable, Equatable {
        public var name: String
        public var registrationNumber: String
        public var representative: String?
        public var openedDate: String?

        public init(
            name: String,
            registrationNumber: String = "",
            representative: String? = nil,
            openedDate: String? = nil
        ) {
            self.name = name
            self.registrationNumber = registrationNumber
            self.representative = representative
            self.openedDate = openedDate
        }
    }

    public struct Trade: Sendable, Equatable {
        public var businessType: String?
        public var businessItem: String?
        public var taxationType: String?
        public var address: String?

        public init(
            businessType: String? = nil,
            businessItem: String? = nil,
            taxationType: String? = nil,
            address: String? = nil
        ) {
            self.businessType = businessType
            self.businessItem = businessItem
            self.taxationType = taxationType
            self.address = address
        }
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        identity: Identity,
        trade: Trade = Trade(),
        note: String? = nil,
        vaultDocsItemID: String? = nil,
        archived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = identity.name
        self.registrationNumber = BusinessNumber.digits(identity.registrationNumber)
        self.representative = identity.representative
        self.openedDate = identity.openedDate
        self.businessType = trade.businessType
        self.businessItem = trade.businessItem
        self.taxationType = trade.taxationType
        self.address = trade.address
        self.note = note
        self.vaultDocsItemID = vaultDocsItemID
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        identity: Identity,
        trade: Trade = Trade(),
        note: String? = nil,
        vaultDocsItemID: String? = nil,
        archived: Bool = false,
        createdAt: Date
    ) {
        self.init(
            id: id,
            identity: identity,
            trade: trade,
            note: note,
            vaultDocsItemID: vaultDocsItemID,
            archived: archived,
            createdAt: createdAt,
            updatedAt: nil
        )
    }

    public init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        registrationNumber: String = "",
        representative: String? = nil,
        openedDate: String? = nil,
        businessType: String? = nil,
        businessItem: String? = nil
    ) {
        self.init(
            id: id,
            identity: Identity(
                name: name,
                registrationNumber: registrationNumber,
                representative: representative,
                openedDate: openedDate
            ),
            trade: Trade(businessType: businessType, businessItem: businessItem)
        )
    }
}

/// 사업자등록번호 검증·표기. 국세청 체크섬(가중치 1,3,7,1,3,7,1,3,5 + 9번째 자리 ×5/10 보정).
public enum BusinessNumber {
    public static func digits(_ raw: String) -> String {
        raw.filter(\.isNumber)
    }

    /// "123-45-67890" 표기. 10자리가 아니면 입력 그대로 돌려준다.
    public static func format(_ raw: String) -> String {
        let d = digits(raw)
        guard d.count == 10 else { return raw }
        let a = d.prefix(3)
        let b = d.dropFirst(3).prefix(2)
        let c = d.suffix(5)
        return "\(a)-\(b)-\(c)"
    }

    /// 체크섬 검증. 빈 문자열은 "미입력"이지 오류가 아니므로 호출부에서 분기한다.
    public static func isValid(_ raw: String) -> Bool {
        let d = digits(raw).compactMap { $0.wholeNumberValue }
        guard d.count == 10 else { return false }
        let weights = [1, 3, 7, 1, 3, 7, 1, 3, 5]
        var sum = 0
        for index in 0..<9 {
            sum += d[index] * weights[index]
        }
        sum += (d[8] * 5) / 10
        return (10 - sum % 10) % 10 == d[9]
    }
}

/// 첨부파일 메타(사업자등록증 이미지 등). 파일 본체는 원장 옆 attachments/ 디렉터리에 산다.
public struct AttachmentRecord: Codable, Sendable, Equatable, Identifiable {
    /// 첨부 소유 엔티티 종류 — 지금은 business, 추후 transaction(영수증) 확장 여지.
    public enum OwnerKind: String, Codable, Sendable {
        case business
        case transaction
    }

    public var id: String
    public var ownerKind: OwnerKind
    public var ownerID: String
    /// 저장 파일명(uuid.확장자) — attachments/<ownerKind>/<ownerID>/<fileName>.
    public var fileName: String
    /// 사용자가 올린 원래 파일명(표시용).
    public var originalName: String
    public var addedAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        ownerKind: OwnerKind,
        ownerID: String,
        fileName: String,
        originalName: String,
        addedAt: Date = .now
    ) {
        self.id = id
        self.ownerKind = ownerKind
        self.ownerID = ownerID
        self.fileName = fileName
        self.originalName = originalName
        self.addedAt = addedAt
    }
}

public enum AttachmentError: Error, Equatable, CustomStringConvertible {
    case sourceMissing(String)

    public var description: String {
        switch self {
        case let .sourceMissing(path): "첨부할 파일이 없습니다: \(path)"
        }
    }
}
