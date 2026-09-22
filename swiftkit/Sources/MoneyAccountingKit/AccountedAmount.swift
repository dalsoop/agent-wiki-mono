import Foundation
import MoneyLedgerModels

/// 계정과목이 붙은 금액 한 건 — 회계 앱이 원장 거래를 계정에 매핑한 결과를 이 Kit 에 넘긴다.
///
/// `amountMinor` 는 **계정의 자연 방향**이다: 매출 계정의 양수는 매출 증가, 비용 계정의 양수는 비용
/// 증가. 환불은 음수 매출, 비용 취소는 음수 비용. 원장의 현금 부호(입금 +, 출금 -)와 다르니
/// 매핑하는 앱이 비용 계정은 부호를 뒤집어서 넘긴다. 금액은 최소단위 Int64(Double 금지).
public struct AccountedAmount: Codable, Sendable, Equatable {
    public var accountCode: AccountCode
    public var amountMinor: Int64
    public var currency: String
    /// "yyyy-MM-dd" — 사전순이 날짜순이라 기간 필터가 문자열 비교로 끝난다.
    public var date: String
    /// 출처(원장 거래 id 등). 집계에는 쓰지 않고 추적용.
    public var sourceID: String?

    public init(
        accountCode: AccountCode,
        amountMinor: Int64,
        currency: String = "KRW",
        date: String,
        sourceID: String? = nil
    ) {
        self.accountCode = accountCode
        self.amountMinor = amountMinor
        self.currency = MoneyAmount.normalizedCurrency(currency)
        self.date = date
        self.sourceID = sourceID
    }
}
