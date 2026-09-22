import Foundation
import LocalizationKit

public enum BacklogPriority: String, Codable, CaseIterable, Comparable, Sendable {
    case p0 = "P0"
    case p1 = "P1"
    case p2 = "P2"
    case p3 = "P3"

    private var rank: Int {
        switch self {
        case .p0: 0
        case .p1: 1
        case .p2: 2
        case .p3: 3
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }
}

public enum BacklogKind: String, Codable, CaseIterable, Sendable {
    case defect
    case feature
}

public enum BacklogStatus: String, Codable, CaseIterable, Sendable {
    case candidate
    case planned
    case inProgress = "in-progress"
    case done
    case dropped
}

public enum BacklogError: Error, Equatable, LocalizedError, Sendable {
    case invalidField(String)
    case notFound(UUID)
    case alreadyExists(UUID)
    case invalidData(String)
    /// 다른 에이전트가 살아 있는 점유를 들고 있다. 같은 일을 두 번 하지 않도록 막는다.
    case claimed(id: UUID, by: String, at: Date)

    public var errorDescription: String? {
        switch self {
        case let .invalidField(field): return CLILocalization.format("BacklogItem.return", field)
        case let .notFound(id): return CLILocalization.format("BacklogItem.return-2", id.uuidString.lowercased())
        case let .alreadyExists(id): return CLILocalization.format("BacklogItem.return-3", id.uuidString.lowercased())
        case let .invalidData(filename): return CLILocalization.format("BacklogItem.return-4", filename)
        case let .claimed(id, by, at):
            let minutes = Int(Date().timeIntervalSince(at) / 60)
            return CLILocalization.format("BacklogItem.return-5", by, String(minutes), id.uuidString.lowercased())
                + "  같은 일을 두 번 하지 않으려면 그 세션과 조율하거나 다른 항목을 잡으십시오.\n"
                + "  넘겨받으려면 --force (점유가 6시간 지나면 자동으로 만료됩니다)."
        }
    }
}

public struct BacklogItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let slug: String
    public let title: String
    public let description: String
    public let source: String
    public let kind: BacklogKind?
    public let priority: BacklogPriority
    public let impact: Int
    public let effort: Int
    public let status: BacklogStatus
    /// 이 항목을 **지금 붙잡고 있는** 에이전트/사람 (`agent:claude@macbook` 형태).
    public let claimedBy: String?
    public let claimedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public struct Content: Equatable, Sendable {
        public var slug: String
        public var title: String
        public var description: String
        public var source: String
        public var kind: BacklogKind?

        public init(
            slug: String,
            title: String,
            description: String,
            source: String,
            kind: BacklogKind? = nil
        ) {
            self.slug = slug
            self.title = title
            self.description = description
            self.source = source
            self.kind = kind
        }
    }

    public struct Scoring: Equatable, Sendable {
        public var priority: BacklogPriority
        public var impact: Int
        public var effort: Int
        public var status: BacklogStatus

        public init(
            priority: BacklogPriority = .p2,
            impact: Int = 3,
            effort: Int = 0,
            status: BacklogStatus = .candidate
        ) {
            self.priority = priority
            self.impact = impact
            self.effort = effort
            self.status = status
        }
    }

    public init(
        id: UUID = UUID(),
        content: Content,
        scoring: Scoring = Scoring(),
        claim: Claim? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {
        let normalizedSlug = content.slug.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = content.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSource = content.source.trimmingCharacters(in: .whitespacesAndNewlines)

        guard Self.isValid(slug: normalizedSlug) else { throw BacklogError.invalidField("slug") }
        guard !normalizedTitle.isEmpty else { throw BacklogError.invalidField("title") }
        guard !normalizedDescription.isEmpty else { throw BacklogError.invalidField("description") }
        guard Self.isValid(source: normalizedSource) else {
            throw BacklogError.invalidField(Self.sourceFieldHint(normalizedSource))
        }
        guard (0...5).contains(scoring.impact) else { throw BacklogError.invalidField("impact") }
        guard (0...5).contains(scoring.effort) else { throw BacklogError.invalidField("effort") }

        self.id = id
        self.slug = normalizedSlug
        self.title = normalizedTitle
        self.description = normalizedDescription
        self.source = normalizedSource
        self.kind = content.kind
        self.priority = scoring.priority
        self.impact = scoring.impact
        self.effort = scoring.effort
        self.status = scoring.status
        let normalizedClaim = claim?.owner?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.claimedBy = (normalizedClaim?.isEmpty ?? true) ? nil : normalizedClaim
        self.claimedAt = self.claimedBy == nil ? nil : Self.normalized(claim?.at ?? Date())
        self.createdAt = Self.normalized(createdAt)
        self.updatedAt = Self.normalized(updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, title, description, source, kind, priority, impact, effort, status
        case claimedBy, claimedAt, createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            content: Content(
                slug: container.decode(String.self, forKey: .slug),
                title: container.decode(String.self, forKey: .title),
                description: container.decode(String.self, forKey: .description),
                source: container.decode(String.self, forKey: .source),
                kind: container.decodeIfPresent(BacklogKind.self, forKey: .kind)
            ),
            scoring: Scoring(
                priority: container.decode(BacklogPriority.self, forKey: .priority),
                impact: container.decode(Int.self, forKey: .impact),
                effort: container.decode(Int.self, forKey: .effort),
                status: container.decode(BacklogStatus.self, forKey: .status)
            ),
            // 예전 파일에는 없다 — 없으면 미점유.
            claim: Claim(
                owner: container.decodeIfPresent(String.self, forKey: .claimedBy),
                at: container.decodeIfPresent(Date.self, forKey: .claimedAt)
            ),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
    }

    /// 점유 변경 지시. `.release` 는 owner 를 지운다.
    public struct Claim: Equatable, Sendable {
        public let owner: String?
        public let at: Date?
        public init(owner: String?, at: Date? = Date()) {
            self.owner = owner
            self.at = owner == nil ? nil : at
        }
        public static let release = Claim(owner: nil)
    }

    /// 점유가 살아 있는가. 세션은 죽어도 점유는 파일에 남으므로 **시간으로 만료**시킨다 —
    /// 안 그러면 죽은 세션의 점유가 항목을 영원히 잠근다.
    public static let claimTTL: TimeInterval = 6 * 60 * 60

    public func claimIsActive(now: Date = Date()) -> Bool {
        guard claimedBy != nil, let claimedAt else { return false }
        return now.timeIntervalSince(claimedAt) < Self.claimTTL
    }

    public static func isValid(slug: String) -> Bool {
        slug.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil
    }

    public static func isValid(source: String) -> Bool {
        // kebab-case 출처 태그(예: session-2026-09-06-room-fix)도 임의 출처로 받는다 —
        // usage 문서와 검증이 어긋나 어떤 --source 도 add 가 막혔던 결함(2026-09)의 재발 방지.
        if isValid(slug: source) { return true }
        if source.hasPrefix("feedback:") { return !source.dropFirst("feedback:".count).isEmpty }
        if source.hasPrefix("evaluation:") {
            return isValid(slug: String(source.dropFirst("evaluation:".count)))
        }
        return false
    }

    /// source 검증 실패 시 입력값과 허용 형식 예시를 함께 보여준다 —
    /// "올바르지 않은 필드입니다: source" 만으로는 어떤 값이 통과하는지 알 수 없었다.
    private static func sourceFieldHint(_ value: String) -> String {
        "source '\(value)' (허용 형식: manual, kebab-case 출처 태그 예: session-2026-09-06-room-fix, feedback:ID, evaluation:SLUG)"
    }

    private static func normalized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 * 1_000) / 1_000)
    }

    func replacing(
        priority: BacklogPriority? = nil,
        status: BacklogStatus? = nil,
        kind: BacklogKind? = nil,
        claim: Claim? = nil,
        updatedAt: Date = Date()
    ) throws -> BacklogItem {
        try BacklogItem(
            id: id,
            content: Content(
                slug: slug,
                title: title,
                description: description,
                source: source,
                kind: kind ?? self.kind
            ),
            scoring: Scoring(
                priority: priority ?? self.priority,
                impact: impact,
                effort: effort,
                status: status ?? self.status
            ),
            claim: claim ?? Claim(owner: claimedBy, at: claimedAt),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public enum BacklogCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "올바르지 않은 ISO-8601 날짜입니다.")
                )
            }
            return date
        }
        return try decoder.decode(type, from: data)
    }
}

public struct ImportSummary: Codable, Equatable, Sendable {
    public let imported: Int
    public let skipped: Int

    public init(imported: Int, skipped: Int) {
        self.imported = imported
        self.skipped = skipped
    }
}
