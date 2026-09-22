import Foundation
import LocalizationKit
import MoneyLedgerModels

/// 세무 기준표 JSON 리소스 로더. 번들은 `ResourceBundle` 이 설치본·테스트 어디서든 찾는다
/// (`Bundle.module` 은 워크트리 삭제 시 설치본 크래시라 lint 가 막는다).
enum TaxRuleResource {
    static let bundleName = "swiftkit_KoreanTaxRulesKit"

    static func load<T: Decodable>(_ type: T.Type, resource name: String) throws -> T {
        let bundle = ResourceBundle.named(bundleName)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw TaxRuleResourceError.missing(name)
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

public enum TaxRuleResourceError: Error, Equatable, CustomStringConvertible {
    case missing(String)
    case noRuleForYear(resource: String, year: Int)
    case unknownIndustryGroup(resource: String, group: String)

    public var description: String {
        switch self {
        case let .missing(name):
            "세무 기준표 리소스를 찾을 수 없습니다: \(name).json"
        case let .noRuleForYear(resource, year):
            "\(resource).json 에 \(year)년 이하 기준이 없습니다 — 연도 키를 추가해야 합니다"
        case let .unknownIndustryGroup(resource, group):
            "\(resource).json 에 업종 그룹 \(group) 기준이 없습니다"
        }
    }
}

/// 연도 키 표 — 요청 연도 이하의 **가장 최근 연도** 규칙을 적용한다(개정이 없으면 이월).
/// JSON 은 `{"2024": {...}, "2026": {...}}` 처럼 연도 문자열 키다.
struct YearKeyed<Value: Decodable & Sendable>: Decodable, Sendable {
    let byYear: [Int: Value]

    init(byYear: [Int: Value]) {
        self.byYear = byYear
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: Value].self)
        var table: [Int: Value] = [:]
        for (key, value) in raw {
            guard let year = Int(key) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "연도 키가 아닙니다: \(key)"))
            }
            table[year] = value
        }
        byYear = table
    }

    func resolve(year: Int) -> (year: Int, value: Value)? {
        guard let best = byYear.keys.filter({ $0 <= year }).max(), let value = byYear[best] else { return nil }
        return (best, value)
    }
}

/// 기준 금액 한 칸 — 금액·확신도·근거 메모.
public struct ThresholdEntry: Codable, Sendable, Equatable {
    public let thresholdMinor: Int64
    public let confidence: RuleConfidence
    public let note: String

    public init(thresholdMinor: Int64, confidence: RuleConfidence, note: String) {
        self.thresholdMinor = thresholdMinor
        self.confidence = confidence
        self.note = note
    }
}

/// 업종 그룹별 수입금액 기준표(연도 키). 간편장부·성실신고 두 표가 같은 모양이다.
struct RevenueThresholdTable: Decodable, Sendable {
    struct Year: Decodable, Sendable {
        let groups: [String: ThresholdEntry]
    }

    let source: String
    let years: YearKeyed<Year>

    static func loadBundled(resource: String) throws -> RevenueThresholdTable {
        try TaxRuleResource.load(RevenueThresholdTable.self, resource: resource)
    }

    func entry(year: Int, group: IndustryGroup, resource: String) throws -> (basisYear: Int, entry: ThresholdEntry) {
        guard let resolved = years.resolve(year: year) else {
            throw TaxRuleResourceError.noRuleForYear(resource: resource, year: year)
        }
        guard let entry = resolved.value.groups[group.rawValue] else {
            throw TaxRuleResourceError.unknownIndustryGroup(resource: resource, group: group.rawValue)
        }
        return (resolved.year, entry)
    }
}
