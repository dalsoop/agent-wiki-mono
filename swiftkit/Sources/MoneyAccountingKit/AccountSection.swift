import Foundation

/// 손익계산서 구획. 자본거래(대표 인출·투입·차입·상환)는 현금은 움직이지만 수익도 비용도 아니라
/// 손익에서 제외한다 — 개인사업자 원장에서 가장 흔한 오분류가 인출금을 비용으로 세는 것이다.
public enum AccountSection: String, Codable, Sendable, CaseIterable {
    case revenue
    case costOfSales
    case sellingAndAdministrative
    case nonOperatingIncome
    case nonOperatingExpense
    case capitalTransaction

    /// 손익에 반영되는 구획인가. 자본거래만 false.
    public var affectsIncome: Bool { self != .capitalTransaction }

    /// 세전이익에 더해지는 방향 — 수익 구획 +1, 비용 구획 -1, 자본거래 0.
    public var incomeSign: Int64 {
        switch self {
        case .revenue, .nonOperatingIncome: 1
        case .costOfSales, .sellingAndAdministrative, .nonOperatingExpense: -1
        case .capitalTransaction: 0
        }
    }

    public func label(korean: Bool) -> String {
        switch self {
        case .revenue: korean ? "매출" : "Revenue"
        case .costOfSales: korean ? "매출원가" : "Cost of sales"
        case .sellingAndAdministrative: korean ? "판매비와관리비" : "Selling and administrative expenses"
        case .nonOperatingIncome: korean ? "영업외수익" : "Non-operating income"
        case .nonOperatingExpense: korean ? "영업외비용" : "Non-operating expenses"
        case .capitalTransaction: korean ? "자본거래(손익 제외)" : "Capital transactions (excluded from income)"
        }
    }
}
