import Foundation
import MoneyInflowKit

public struct MatchItem: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let provider: String
    public let summary: String
    public let target: String
    public let categories: [String]
    public let deadlineDays: Int?
    public let acceptingNow: Bool
    public let periodRaw: String
    public let supportAmount: String?
    public let interestRate: String?
    public let maxAmount: String?
    public let benefitAmount: String?
    public let eligibilityNote: String?
    public let applyUrl: String?
    public let detailUrl: String?

    public init(
        id: String,
        title: String,
        provider: String,
        summary: String,
        target: String,
        categories: [String],
        deadlineDays: Int?,
        acceptingNow: Bool,
        periodRaw: String,
        supportAmount: String? = nil,
        interestRate: String? = nil,
        maxAmount: String? = nil,
        benefitAmount: String? = nil,
        eligibilityNote: String? = nil,
        applyUrl: String? = nil,
        detailUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.provider = provider
        self.summary = summary
        self.target = target
        self.categories = categories
        self.deadlineDays = deadlineDays
        self.acceptingNow = acceptingNow
        self.periodRaw = periodRaw
        self.supportAmount = supportAmount
        self.interestRate = interestRate
        self.maxAmount = maxAmount
        self.benefitAmount = benefitAmount
        self.eligibilityNote = eligibilityNote
        self.applyUrl = applyUrl
        self.detailUrl = detailUrl
    }
}

public struct MatchResult: Codable, Sendable, Equatable {
    public let matched: [MatchItem]
    public let count: Int
    public let total: Int
    public let note: String

    public init(matched: [MatchItem], count: Int, total: Int, note: String) {
        self.matched = matched
        self.count = count
        self.total = total
        self.note = note
    }
}

public struct StatusResult: Codable, Sendable, Equatable {
    public let catalogCount: Int
    public let configPath: String
    public let configExists: Bool
    public let region: String
    public let businessTypes: [String]
    public let categories: [String]
    public let note: String

    public init(
        catalogCount: Int,
        configPath: String,
        configExists: Bool,
        region: String,
        businessTypes: [String],
        categories: [String],
        note: String
    ) {
        self.catalogCount = catalogCount
        self.configPath = configPath
        self.configExists = configExists
        self.region = region
        self.businessTypes = businessTypes
        self.categories = categories
        self.note = note
    }
}

public enum CLIParse {
    public static func types(_ s: String) -> Set<BusinessType> {
        Set(s.split(separator: ",").compactMap { BusinessType(rawValue: String($0).trimmingCharacters(in: .whitespaces)) })
    }

    public static func region(_ s: String) -> KoreanRegion? {
        KoreanRegion(rawValue: s.trimmingCharacters(in: .whitespaces))
    }

    public static func cats(_ s: String) -> Set<SupportCategory> {
        Set(s.split(separator: ",").compactMap { SupportCategory(rawValue: String($0).trimmingCharacters(in: .whitespaces)) })
    }

    public static func matchItem(from p: GovernmentProgram) -> MatchItem {
        MatchItem(
            id: p.id,
            title: p.title,
            provider: p.providerName,
            summary: p.summary,
            target: p.targetAudienceText,
            categories: p.categories.map(\.displayName).sorted(),
            deadlineDays: p.daysUntilClose(),
            acceptingNow: p.isAcceptingNow,
            periodRaw: p.period.rawText,
            applyUrl: p.applyURL?.absoluteString,
            detailUrl: p.detailURL?.absoluteString
        )
    }

    public static func matchItem(from p: SubsidyProgram) -> MatchItem {
        MatchItem(
            id: p.id,
            title: p.title,
            provider: p.providerName,
            summary: p.summary,
            target: p.targetAudienceText,
            categories: p.categories.map(\.displayName).sorted(),
            deadlineDays: p.daysUntilClose(),
            acceptingNow: p.isAcceptingNow,
            periodRaw: p.period.rawText,
            supportAmount: p.supportAmount,
            eligibilityNote: p.eligibilityNote,
            applyUrl: p.applyURL?.absoluteString,
            detailUrl: p.detailURL?.absoluteString
        )
    }

    public static func matchItem(from p: LoanProduct) -> MatchItem {
        MatchItem(
            id: p.id,
            title: p.title,
            provider: p.providerName,
            summary: p.summary,
            target: p.targetAudienceText,
            categories: p.categories.map(\.displayName).sorted(),
            deadlineDays: p.daysUntilClose(),
            acceptingNow: p.isAcceptingNow,
            periodRaw: p.period.rawText,
            interestRate: p.interestRate,
            maxAmount: p.maxAmount,
            eligibilityNote: p.eligibilityNote,
            applyUrl: p.applyURL?.absoluteString,
            detailUrl: p.detailURL?.absoluteString
        )
    }

    public static func matchItem(from p: TaxBenefit) -> MatchItem {
        MatchItem(
            id: p.id,
            title: p.title,
            provider: p.providerName,
            summary: p.summary,
            target: p.targetAudienceText,
            categories: p.categories.map(\.displayName).sorted(),
            deadlineDays: p.daysUntilClose(),
            acceptingNow: p.isAcceptingNow,
            periodRaw: p.period.rawText,
            benefitAmount: p.benefitAmount,
            eligibilityNote: p.eligibilityNote,
            applyUrl: p.applyURL?.absoluteString,
            detailUrl: p.detailURL?.absoluteString
        )
    }
}
