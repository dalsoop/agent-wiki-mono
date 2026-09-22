import Foundation
import MoneyLedgerModels

/// 부가가치세 예정고지 소액 생략 기준(부가가치세법 제48조 제3항) — 직전 과세기간 납부세액의 50% 가
/// 기준 미만이면 고지하지 않는다. 금액은 `Resources/vat-preliminary-notice.json`(연도 키).
public struct VATPreliminaryNoticeRule: Sendable {
    public static let resourceName = "vat-preliminary-notice"

    public struct Entry: Codable, Sendable, Equatable {
        public let minimumNoticeMinor: Int64
        public let confidence: RuleConfidence
        public let note: String

        public init(minimumNoticeMinor: Int64, confidence: RuleConfidence, note: String) {
            self.minimumNoticeMinor = minimumNoticeMinor
            self.confidence = confidence
            self.note = note
        }
    }

    let years: YearKeyed<Entry>

    public init(byYear: [Int: Entry]) {
        years = YearKeyed(byYear: byYear)
    }

    init(years: YearKeyed<Entry>) {
        self.years = years
    }

    public static func loadBundled() throws -> VATPreliminaryNoticeRule {
        try TaxRuleResource.load(Document.self, resource: resourceName).rule
    }

    public func entry(for year: Int) -> (basisYear: Int, entry: Entry)? {
        guard let resolved = years.resolve(year: year) else { return nil }
        return (resolved.year, resolved.value)
    }

    struct Document: Decodable {
        let source: String
        let years: YearKeyed<Entry>

        var rule: VATPreliminaryNoticeRule { VATPreliminaryNoticeRule(years: years) }
    }
}
