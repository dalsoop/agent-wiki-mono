import Foundation

/// 소득세법 간편장부 표준손익계산서 계정과목. 판관비 세목은 간편장부 소득금액계산서 부속서류의
/// 항목을 따르고, 매출원가에는 gujo.ai 운영에 필요한 AI API 사용료·서버/클라우드를 둔다
/// (해외 AI API·서버 = 매출원가, 개발 도구 SaaS = 판관비 지급수수료 — 위키 9261be4f).
/// raw 값이 앱 간 교환 문자열이다 — KoreanTaxRulesKit 은 이 enum 없이 raw 문자열만 받는다.
public enum AccountCode: String, Codable, Sendable, CaseIterable {
    // 매출
    case sales

    // 매출원가
    case purchases
    case aiApiUsage
    case hostingAndCloud

    // 판매비와관리비
    case salaries
    case employeeBenefits
    case travelAndTransportation
    case entertainment
    case communication
    case utilities
    case taxesAndDues
    case depreciation
    case rent
    case insurance
    case repairs
    case vehicleMaintenance
    case educationAndTraining
    case booksAndPrinting
    case supplies
    case fees
    case advertising
    case outsourcing
    case intangibleAmortization
    case miscellaneousExpense

    // 영업외수익
    case interestIncome
    case foreignExchangeGain
    case miscellaneousIncome

    // 영업외비용
    case interestExpense
    case foreignExchangeLoss
    case donations
    case miscellaneousLoss

    // 자본거래 — 손익 제외
    case ownerDrawing
    case ownerContribution
    case loanProceeds
    case loanRepayment

    public var section: AccountSection { descriptor.section }

    public var descriptor: AccountCodeDescriptor { AccountCodeCatalog.descriptor(for: self) }

    public func label(korean: Bool) -> String {
        korean ? descriptor.korean : descriptor.english
    }

    /// 표준손익계산서 표시 순서 — `allCases` 선언 순.
    public var displayOrder: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    public static func codes(in section: AccountSection) -> [AccountCode] {
        allCases.filter { $0.section == section }
    }

    /// 앱 간 교환 문자열(raw) 또는 ko/en 표시명으로 코드를 찾는다. 대소문자·양끝 공백 무시.
    public static func resolve(_ text: String) -> AccountCode? {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return allCases.first { code in
            code.rawValue.lowercased() == needle
                || code.label(korean: true).lowercased() == needle
                || code.label(korean: false).lowercased() == needle
        }
    }
}
