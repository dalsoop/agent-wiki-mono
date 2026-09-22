import Foundation

/// 부가가치세 10/110 분리. 세액 = 총액 × 10 ÷ 110 (원 미만 절사), 공급가액 = 총액 − 세액.
/// 세율 10% 는 부가가치세법 제30조의 법정 세율이라 코드 상수로 둔다(연도 키 리소스 대상이 아니다).
/// 음수(환불)는 0 방향 절사로 대칭 — 원 거래와 환불이 정확히 상쇄된다.
public enum VATSplit {
    public struct Result: Codable, Sendable, Equatable {
        public let grossMinor: Int64
        public let supplyMinor: Int64
        public let vatMinor: Int64

        public init(grossMinor: Int64, supplyMinor: Int64, vatMinor: Int64) {
            self.grossMinor = grossMinor
            self.supplyMinor = supplyMinor
            self.vatMinor = vatMinor
        }
    }

    /// 세율 분자·분모 — 10/110 (공급대가에서 세액을 뽑을 때), 1/10 (공급가액에서 세액을 더할 때).
    public static let rateNumerator: Int64 = 10
    public static let rateDenominator: Int64 = 100

    /// 공급대가(총액) → 세액·공급가액. 예: 11,111 → 세액 1,010 · 공급가액 10,101.
    public static func split(grossMinor: Int64) -> Result {
        let vat = grossMinor * rateNumerator / (rateDenominator + rateNumerator)
        return Result(grossMinor: grossMinor, supplyMinor: grossMinor - vat, vatMinor: vat)
    }

    /// 공급가액 → 세액·공급대가. 세액은 공급가액의 10% 원 미만 절사.
    public static func gross(supplyMinor: Int64) -> Result {
        let vat = supplyMinor * rateNumerator / rateDenominator
        return Result(grossMinor: supplyMinor + vat, supplyMinor: supplyMinor, vatMinor: vat)
    }
}
