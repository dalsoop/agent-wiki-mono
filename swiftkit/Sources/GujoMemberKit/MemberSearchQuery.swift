import Foundation

/// 회원 검색 조건. 네트워크 없이 쿼리스트링으로만 직렬화한다.
public struct MemberSearchQuery: Sendable, Equatable, Codable {
    public var email: String?
    public var name: String?
    public var tag: String?
    public var locale: String?
    public var limit: Int
    public var cursor: String?

    public static let defaultLimit = 50

    public init(
        email: String? = nil,
        name: String? = nil,
        tag: String? = nil,
        locale: String? = nil,
        limit: Int = MemberSearchQuery.defaultLimit,
        cursor: String? = nil
    ) {
        self.email = Self.trim(email)
        self.name = Self.trim(name)
        self.tag = Self.trim(tag)
        self.locale = Self.trim(locale)
        self.limit = max(1, limit)
        self.cursor = Self.trim(cursor)
    }

    public var queryItems: [URLQueryItem] {
        let filters: [(String, String?)] = [
            ("email", email),
            ("name", name),
            ("tag", tag),
            ("locale", locale),
        ]
        let present = filters.compactMap { key, value in
            value.map { URLQueryItem(name: key, value: $0) }
        }
        let limitItem = URLQueryItem(name: "limit", value: String(limit))
        let cursorItem = cursor.map { URLQueryItem(name: "cursor", value: $0) }
        return present + [limitItem] + [cursorItem].compactMap { $0 }
    }

    /// `email=a@b.c&limit=20` 형태. 키 순서는 `queryItems` 와 같다.
    public var serializedQuery: String {
        queryItems.map { item in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? item.name
            let value = (item.value ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "\(name)=\(value)"
        }.joined(separator: "&")
    }

    public func matches(_ member: Member) -> Bool {
        emailMatches(member) && nameMatches(member) && tagMatches(member) && localeMatches(member)
    }

    private func emailMatches(_ member: Member) -> Bool {
        guard let email else { return true }
        return member.email.lowercased().contains(email.lowercased())
    }

    private func nameMatches(_ member: Member) -> Bool {
        guard let name else { return true }
        return member.displayName.lowercased().contains(name.lowercased())
    }

    private func tagMatches(_ member: Member) -> Bool {
        guard let tag else { return true }
        return member.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    private func localeMatches(_ member: Member) -> Bool {
        guard let locale else { return true }
        return (member.locale ?? "").caseInsensitiveCompare(locale) == .orderedSame
    }

    private static func trim(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
