import Foundation

/// 고객 카드의 최근 문의 슬롯. Support Desk 가 첫 소비자.
public struct MemberRecentInquiry: Sendable, Equatable, Hashable, Codable {
    public var id: String
    public var subject: String
    public var status: String
    public var createdAt: Date?
    public var preview: String?

    public init(
        id: String,
        subject: String,
        status: String,
        createdAt: Date? = nil,
        preview: String? = nil
    ) {
        self.id = id
        self.subject = subject
        self.status = status
        self.createdAt = createdAt
        self.preview = preview
    }

    enum CodingKeys: String, CodingKey {
        case id
        case subject
        case status
        case createdAt = "created_at"
        case preview
        case latestBodyPreview = "latest_body_preview"
        case userId = "user_id"
        case userEmail = "user_email"
        case category
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try MemberJSON.decodeIdentifier(container, key: CodingKeys.id)
        subject = (try container.decodeIfPresent(String.self, forKey: .subject) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        status = (try container.decodeIfPresent(String.self, forKey: .status) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
            ?? container.decodeIfPresent(String.self, forKey: .latestBodyPreview)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(subject, forKey: .subject)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(preview, forKey: .preview)
    }

    /// 문의 JSON 에서 회원 식별만 뽑는다 (`user_id` · `user_email`).
    public func memberStub(userId: String?, email: String?) -> Member? {
        let resolvedEmail = (email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedId = (userId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if resolvedId.isEmpty && resolvedEmail.isEmpty { return nil }
        return Member(
            id: resolvedId.isEmpty ? resolvedEmail : resolvedId,
            email: resolvedEmail,
            createdAt: createdAt
        )
    }
}

/// `GET /api/support/staff/inquiries` 목록 봉투.
public struct StaffInquiryListEnvelope: Sendable, Equatable, Decodable {
    public var data: [StaffInquiryRecord]
}

/// support/staff 문의 한 줄 — 회원 카드의 최근 문의 + 회원 stub 를 만든다.
public struct StaffInquiryRecord: Sendable, Equatable, Decodable {
    public var inquiry: MemberRecentInquiry
    public var userId: String?
    public var userEmail: String?

    enum CodingKeys: String, CodingKey {
        case id, subject, status, preview, category
        case createdAt = "created_at"
        case latestBodyPreview = "latest_body_preview"
        case userId = "user_id"
        case userEmail = "user_email"
    }

    public init(from decoder: Decoder) throws {
        inquiry = try MemberRecentInquiry(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = MemberJSON.decodeOptionalIdentifier(container, key: CodingKeys.userId)
        userEmail = try container.decodeIfPresent(String.self, forKey: .userEmail)
    }

    public var member: Member {
        Member(
            id: userId ?? inquiry.id,
            email: userEmail ?? "",
            createdAt: inquiry.createdAt,
            tags: []
        )
    }
}
