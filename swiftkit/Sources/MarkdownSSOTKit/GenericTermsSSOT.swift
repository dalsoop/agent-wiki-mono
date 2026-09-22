import Foundation

/// 딕셔너리 또는 임의의 치환 쌍 목록으로부터 동작하는 다형적 `AlignRuleProvider` 구현체.
/// 특정 도메인 구조에 종속되지 않고 임의의 텍스트/용어 정렬 규칙을 전달할 때 사용됩니다.
public struct GenericTermsSSOT: Codable, Sendable, Equatable, AlignRuleProvider {
    public struct Rule: Codable, Sendable, Equatable {
        public let from: String
        public let to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    public let identifier: String
    public let rules: [Rule]

    public var ledgerIdentifier: String { identifier }

    public init(identifier: String = "GenericTermsSSOT", rules: [(from: String, to: String)]) {
        self.identifier = identifier
        self.rules = rules.map { Rule(from: $0.from, to: $0.to) }
    }

    public init(identifier: String = "GenericTermsSSOT", mapping: [String: String]) {
        self.identifier = identifier
        self.rules = mapping
            .filter { $0.key != $0.value }
            .map { Rule(from: $0.key, to: $0.value) }
            .sorted { $0.from.count > $1.from.count }
    }

    public func replacementRules() -> [(from: String, to: String)] {
        rules
            .filter { $0.from != $0.to }
            .map { (from: $0.from, to: $0.to) }
            .sorted { $0.from.count > $1.from.count }
    }

    public func validate() -> [String] {
        var seenFrom = Set<String>()
        return rules.flatMap { rule in
            let issues = issuesForRule(rule, seenFrom: seenFrom)
            seenFrom.insert(rule.from)
            return issues
        }
    }

    private func issuesForRule(_ rule: Rule, seenFrom: Set<String>) -> [String] {
        [
            rule.from.isEmpty ? "치환 대상(from) 문자열이 비어있습니다." : nil,
            rule.from == rule.to ? "동일 문자열 치환 규칙이 감지되었습니다: '\(rule.from)' -> '\(rule.to)'" : nil,
            seenFrom.contains(rule.from) ? "중복된 치환 대상이 감지되었습니다: '\(rule.from)'" : nil,
        ].compactMap { $0 }
    }
}
