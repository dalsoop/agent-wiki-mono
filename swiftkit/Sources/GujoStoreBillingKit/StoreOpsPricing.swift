import Foundation

/// Setapp 2x Pricing SSOT
///
/// 사용자 결정 2026-09-03:
/// - 경쟁사(Setapp) 동일 가격 대비 2배.
/// - 단품: 카탈로그 원화를 달러(세금 별도)로 전환 후 2x, .99 라운딩. 구독 포함($0) 상품은 제외.
///   (₩9,900 → $13.99 · ₩14,900 → $19.99 · ₩39,000 → $59.99)
/// - 구독 3플랜 신설:
///   1. Mac: $29.99/월 (맥 1대) / 연 결제 $19.99/월
///   2. Mac + iOS: $37.99/월 (맥 1+iOS 4) / 연 결제 $24.99/월
///   3. Power User: $45.99/월 (맥 4+iOS 4) / 연 결제 $29.99/월
///   7일 무료 체험. 기존 'AI Tools Subscription' $99/년 플랜 폐기/이전.
/// - 접근 기간: 단품 access_duration_days = 365 로 통일 (기존 36500 혼재 정리).
public enum StoreOpsPricing: Sendable {

    public static let standardAccessDurationDays: Int = 365
    public static let subscriptionTrialDays: Int = 7

    // MARK: - Standalone USD Pricing (2x Setapp-equivalent / KRW convert)

    public struct StandalonePrice: Sendable, Equatable, Codable {
        public let krw: Int
        public let priceUsdCents: Int
        public let accessDurationDays: Int
        public let isSubscriptionIncluded: Bool

        public var usdDollars: Double {
            Double(priceUsdCents) / 100.0
        }

        public var formattedUSD: String {
            String(format: "$%.2f", usdDollars)
        }

        public init(
            krw: Int,
            priceUsdCents: Int,
            accessDurationDays: Int = StoreOpsPricing.standardAccessDurationDays,
            isSubscriptionIncluded: Bool = false
        ) {
            self.krw = krw
            self.priceUsdCents = priceUsdCents
            self.accessDurationDays = accessDurationDays
            self.isSubscriptionIncluded = isSubscriptionIncluded
        }
    }

    /// 원화(KRW) 금액을 달러 센트(USD cents, .99 라운딩)로 변환 (2x 반영).
    /// - ₩9,900 -> 1399 ($13.99)
    /// - ₩14,900 -> 1999 ($19.99)
    /// - ₩39,000 -> 5999 ($59.99)
    /// - 구독 포함($0) 또는 0원 이하는 0 (isSubscriptionIncluded = true 시 0 반환)
    public static func convertKRWToUSDCents(krw: Int, isSubscriptionIncluded: Bool = false) -> Int {
        if isSubscriptionIncluded || krw <= 0 {
            return 0
        }

        switch krw {
        case 9_900:
            return 1_399
        case 14_900:
            return 1_999
        case 19_900:
            return 2_999
        case 29_000, 29_900:
            return 4_399
        case 39_000:
            return 5_999
        case 49_000, 49_900:
            return 7_499
        default:
            let netKRW = Double(krw) / 1.1
            let usdBase = (netKRW / 1400.0) * 2.0
            let roundedDollars = max(1.0, floor(usdBase)) + 0.99
            return Int(round(roundedDollars * 100.0))
        }
    }

    /// 단품 상품에 대한 계산된 StandalonePrice 반환
    public static func calculateStandalonePrice(
        krw: Int,
        accessDurationDays: Int? = nil,
        isSubscriptionIncluded: Bool = false
    ) -> StandalonePrice {
        let cents = convertKRWToUSDCents(krw: krw, isSubscriptionIncluded: isSubscriptionIncluded)
        let normalizedDays = normalizeAccessDurationDays(accessDurationDays)
        return StandalonePrice(
            krw: krw,
            priceUsdCents: cents,
            accessDurationDays: normalizedDays,
            isSubscriptionIncluded: isSubscriptionIncluded
        )
    }

    /// access_duration_days 를 365 로 정규화 (기존 36500 혼재 정리)
    public static func normalizeAccessDurationDays(_ days: Int? = nil) -> Int {
        standardAccessDurationDays
    }

    // MARK: - Subscription Tiers (3 Plans, Setapp 2x)

    public enum SubscriptionTierID: String, CaseIterable, Sendable, Codable {
        case mac = "mac"
        case macIOS = "mac_ios"
        case powerUser = "power_user"
    }

    public struct SubscriptionPlan: Sendable, Equatable, Identifiable, Codable {
        public var id: SubscriptionTierID { tierId }
        public let tierId: SubscriptionTierID
        public let name: String
        public let slug: String
        public let summary: String
        public let macCount: Int
        public let iosCount: Int
        public let monthlyPriceUsdCents: Int
        public let annualMonthlyEquivalentUsdCents: Int
        public let annualTotalPriceUsdCents: Int
        public let trialDays: Int
        public let isActive: Bool

        public var formattedMonthlyPrice: String {
            String(format: "$%.2f/mo", Double(monthlyPriceUsdCents) / 100.0)
        }

        public var formattedAnnualMonthlyRate: String {
            String(format: "$%.2f/mo", Double(annualMonthlyEquivalentUsdCents) / 100.0)
        }

        public var formattedAnnualTotal: String {
            String(format: "$%.2f/yr", Double(annualTotalPriceUsdCents) / 100.0)
        }

        public init(
            tierId: SubscriptionTierID,
            name: String,
            slug: String,
            summary: String,
            macCount: Int,
            iosCount: Int,
            monthlyPriceUsdCents: Int,
            annualMonthlyEquivalentUsdCents: Int,
            trialDays: Int = StoreOpsPricing.subscriptionTrialDays,
            isActive: Bool = true
        ) {
            self.tierId = tierId
            self.name = name
            self.slug = slug
            self.summary = summary
            self.macCount = macCount
            self.iosCount = iosCount
            self.monthlyPriceUsdCents = monthlyPriceUsdCents
            self.annualMonthlyEquivalentUsdCents = annualMonthlyEquivalentUsdCents
            self.annualTotalPriceUsdCents = annualMonthlyEquivalentUsdCents * 12
            self.trialDays = trialDays
            self.isActive = isActive
        }
    }

    /// 구독 3플랜 정본
    /// 1. Mac: $29.99/월 (맥 1대) / 연 결제 $19.99/월
    /// 2. Mac + iOS: $37.99/월 (맥 1+iOS 4) / 연 결제 $24.99/월
    /// 3. Power User: $45.99/월 (맥 4+iOS 4) / 연 결제 $29.99/월
    /// 모두 7일 무료체험.
    public static let subscriptionPlans: [SubscriptionPlan] = [
        SubscriptionPlan(
            tierId: .mac,
            name: "Mac",
            slug: "mac",
            summary: "맥 1대 전용 플랜",
            macCount: 1,
            iosCount: 0,
            monthlyPriceUsdCents: 2_999,
            annualMonthlyEquivalentUsdCents: 1_999
        ),
        SubscriptionPlan(
            tierId: .macIOS,
            name: "Mac + iOS",
            slug: "mac-ios",
            summary: "맥 1대 + iOS 4대 플랜",
            macCount: 1,
            iosCount: 4,
            monthlyPriceUsdCents: 3_799,
            annualMonthlyEquivalentUsdCents: 2_499
        ),
        SubscriptionPlan(
            tierId: .powerUser,
            name: "Power User",
            slug: "power-user",
            summary: "맥 4대 + iOS 4대 파워유저 플랜",
            macCount: 4,
            iosCount: 4,
            monthlyPriceUsdCents: 4_599,
            annualMonthlyEquivalentUsdCents: 2_999
        ),
    ]

    // MARK: - Legacy Plan

    public struct LegacyPlan: Sendable, Equatable, Codable {
        public let name: String
        public let annualPriceUsdCents: Int
        public let status: String

        public init(
            name: String = "AI Tools Subscription",
            annualPriceUsdCents: Int = 9_900,
            status: String = "deprecated"
        ) {
            self.name = name
            self.annualPriceUsdCents = annualPriceUsdCents
            self.status = status
        }
    }

    public static let legacyAIToolsPlan = LegacyPlan()
}
