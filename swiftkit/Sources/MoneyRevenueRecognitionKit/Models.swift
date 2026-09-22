import Foundation

public enum ContractTerm: Sendable, Equatable {
    case monthly
    case annual
    case multiYear(years: Int)
    case customDays(Int)
}

public enum BillingSchedule: Sendable, Equatable {
    case upfront      // 선불 (전액 결제)
    case monthly      // 월별 결제
    case quarterly    // 분기별 결제
    case annual       // 연간 결제
}

public struct DeferredRevenue: Sendable, Equatable {
    public let totalAmount: Decimal
    public var recognizedAmount: Decimal
    public var remainingAmount: Decimal {
        return totalAmount - recognizedAmount
    }
    
    public init(totalAmount: Decimal, recognizedAmount: Decimal = 0) {
        self.totalAmount = totalAmount
        self.recognizedAmount = recognizedAmount
    }
}

public struct RevenueScheduleEntry: Sendable, Equatable {
    public let periodStart: Date
    public let periodEnd: Date
    public let recognizedRevenue: Decimal
    public let remainingDeferredRevenue: Decimal
    
    public init(periodStart: Date, periodEnd: Date, recognizedRevenue: Decimal, remainingDeferredRevenue: Decimal) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.recognizedRevenue = recognizedRevenue
        self.remainingDeferredRevenue = remainingDeferredRevenue
    }
}
