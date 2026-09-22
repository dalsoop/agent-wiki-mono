import Foundation
import LocalizationKit
import MoneyLedgerModels

/// 원장 category 문자열·적요 패턴 → 계정과목 **제안** 표. 매핑 규칙의 정본은 나중 회계 앱이
/// 소유한다(건별 override 포함) — 여기는 기본 제안만 하고, 규칙마다 confidence 를 달아 앱이
/// 검토 필요 항목을 화면에 드러내게 한다. 표 본문은 `Resources/default-account-mapping.json`.
public struct DefaultAccountMapping: Sendable {
    /// 현금 흐름 방향 — "이자"(수익/비용)·"PayPal"(정산 입금/수수료)처럼 같은 낱말이 방향에 따라
    /// 다른 계정으로 가는 경우를 가른다.
    public enum FlowDirection: String, Codable, Sendable, CaseIterable {
        case inflow
        case outflow
    }

    public struct Rule: Codable, Sendable, Equatable {
        public let id: String
        public let accountCode: AccountCode
        /// 원장 category 완전일치(대소문자·양끝 공백 무시).
        public let categories: [String]
        /// 적요 부분일치(대소문자 무시).
        public let descriptionPatterns: [String]
        /// nil 이면 방향 무관.
        public let flow: FlowDirection?
        public let confidence: RuleConfidence
        public let note: String

        public init(
            id: String,
            accountCode: AccountCode,
            categories: [String] = [],
            descriptionPatterns: [String] = [],
            flow: FlowDirection? = nil,
            confidence: RuleConfidence,
            note: String
        ) {
            self.id = id
            self.accountCode = accountCode
            self.categories = categories
            self.descriptionPatterns = descriptionPatterns
            self.flow = flow
            self.confidence = confidence
            self.note = note
        }

        /// JSON 에서 `categories`·`descriptionPatterns`·`flow` 는 생략 가능 — 표를 짧게 쓰기 위해서다.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            accountCode = try container.decode(AccountCode.self, forKey: .accountCode)
            categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
            descriptionPatterns = try container.decodeIfPresent([String].self, forKey: .descriptionPatterns) ?? []
            flow = try container.decodeIfPresent(FlowDirection.self, forKey: .flow)
            confidence = try container.decode(RuleConfidence.self, forKey: .confidence)
            note = try container.decode(String.self, forKey: .note)
        }
    }

    public enum Match: Sendable, Equatable {
        /// category 가 계정 raw/표시명과 바로 일치 — 표 없이 코드가 판정한다.
        case accountLabel(String)
        case category(String)
        case description(String)
    }

    public struct Suggestion: Sendable, Equatable {
        public let accountCode: AccountCode
        public let ruleID: String
        public let match: Match
        public let confidence: RuleConfidence
        public let note: String
    }

    public static let bundledResourceName = "default-account-mapping"
    static let bundleName = "swiftkit_MoneyAccountingKit"
    static let accountLabelRuleID = "account-label"

    public let version: Int
    public let rules: [Rule]

    public init(version: Int = 0, rules: [Rule]) {
        self.version = version
        self.rules = rules
    }

    /// 번들 리소스에서 읽는다. 설치본·테스트 어디서든 `ResourceBundle` 이 번들을 찾는다(Bundle.module 금지).
    public static func loadBundled() throws -> DefaultAccountMapping {
        let bundle = ResourceBundle.named(bundleName)
        guard let url = bundle.url(forResource: bundledResourceName, withExtension: "json") else {
            throw AccountMappingResourceError.missing(bundledResourceName)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Document.self, from: data).mapping
    }

    /// 첫 일치 규칙이 이긴다 — 표의 순서가 우선순위다. 계정 표시명과 바로 일치하는 category 가 최우선.
    public func suggest(category: String?, description: String, flow: FlowDirection? = nil) -> Suggestion? {
        if let category, let code = AccountCode.resolve(category) {
            return Suggestion(
                accountCode: code,
                ruleID: Self.accountLabelRuleID,
                match: .accountLabel(category),
                confidence: .confirmed,
                note: "category 가 계정과목 이름과 일치"
            )
        }
        let normalizedCategory = category.map(Self.normalize) ?? ""
        let normalizedDescription = Self.normalize(description)
        for rule in rules where rule.accepts(flow: flow) {
            if let hit = rule.match(category: normalizedCategory, description: normalizedDescription) {
                return Suggestion(accountCode: rule.accountCode, ruleID: rule.id, match: hit, confidence: rule.confidence, note: rule.note)
            }
        }
        return nil
    }

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    struct Document: Decodable {
        let version: Int
        let rules: [Rule]

        var mapping: DefaultAccountMapping { DefaultAccountMapping(version: version, rules: rules) }
    }
}

extension DefaultAccountMapping.Rule {
    /// 규칙에 방향이 없거나 호출자가 방향을 모르면(nil) 통과 — 방향은 좁히는 힌트지 필수 입력이 아니다.
    func accepts(flow: DefaultAccountMapping.FlowDirection?) -> Bool {
        guard let required = self.flow, let flow else { return true }
        return required == flow
    }

    /// category 완전일치 → 적요 부분일치 순. 입력은 이미 정규화돼 있다.
    func match(category: String, description: String) -> DefaultAccountMapping.Match? {
        if !category.isEmpty, let hit = categories.first(where: { DefaultAccountMapping.normalize($0) == category }) {
            return .category(hit)
        }
        guard !description.isEmpty else { return nil }
        if let hit = descriptionPatterns.first(where: { description.contains(DefaultAccountMapping.normalize($0)) }) {
            return .description(hit)
        }
        return nil
    }
}

public enum AccountMappingResourceError: Error, Equatable, CustomStringConvertible {
    case missing(String)

    public var description: String {
        switch self {
        case let .missing(name): "계정 제안 표 리소스를 찾을 수 없습니다: \(name).json"
        }
    }
}
