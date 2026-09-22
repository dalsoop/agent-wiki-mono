import Foundation
import MoneyLedgerModels

/// 현금영수증 의무발행업종 판정(소득세법 제162조의3, 시행령 별표 3의3). 의무발행업종은 건당 거래금액
/// (부가세 포함) 기준 이상이면 소비자가 요구하지 않아도 발급해야 한다. 업종 목록은
/// `Resources/cash-receipt-mandatory-industries.json` — 목록이 전체가 아니므로 미등재 업종은 검토 필요다.
public enum CashReceiptMandatoryIssuance {
    public static let resourceName = "cash-receipt-mandatory-industries"

    public struct Judgement: Codable, Sendable, Equatable {
        public let industry: String
        public let isMandatoryIndustry: Bool
        /// 리소스 목록에 등재된 업종인가. false 면 `unlisted` 기본값이 적용된 것.
        public let isListed: Bool
        /// 의무 발급 기준 건당 금액(부가세 포함).
        public let mandatoryAmountMinor: Int64
        public let confidence: RuleConfidence
        public let note: String
    }

    struct Table: Decodable, Sendable {
        struct Industry: Decodable, Sendable {
            let name: String
            let applies: Bool
            let confidence: RuleConfidence
            let note: String
        }

        struct Unlisted: Decodable, Sendable {
            let confidence: RuleConfidence
            let note: String
        }

        let source: String
        let mandatoryAmountMinor: Int64
        let amountConfidence: RuleConfidence
        let amountNote: String
        let industries: [Industry]
        let unlisted: Unlisted

        func industry(named name: String) -> Industry? {
            let needle = CashReceiptMandatoryIssuance.normalize(name)
            return industries.first { CashReceiptMandatoryIssuance.normalize($0.name) == needle }
        }
    }

    public static func judge(industry: String) throws -> Judgement {
        let table = try TaxRuleResource.load(Table.self, resource: resourceName)
        guard let listed = table.industry(named: industry) else {
            return Judgement(
                industry: industry, isMandatoryIndustry: false, isListed: false,
                mandatoryAmountMinor: table.mandatoryAmountMinor,
                confidence: table.unlisted.confidence,
                note: table.unlisted.note
            )
        }
        return Judgement(
            industry: industry, isMandatoryIndustry: listed.applies, isListed: true,
            mandatoryAmountMinor: table.mandatoryAmountMinor,
            confidence: listed.confidence.merged(with: table.amountConfidence),
            note: listed.note
        )
    }

    /// 의무발행업종이고 건당 금액이 기준 이상이면 요구 없이도 발급.
    public static func requiresIssuance(industry: String, amountMinor: Int64) throws -> Bool {
        let judgement = try judge(industry: industry)
        return judgement.isMandatoryIndustry && amountMinor >= judgement.mandatoryAmountMinor
    }

    static func normalize(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && $0 != "," && $0 != "·" }
    }
}
