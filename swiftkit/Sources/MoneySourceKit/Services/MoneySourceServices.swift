import Foundation
import MoneyInflowKit

public struct GovernmentProgramLookupService: Sendable {
    private let crawler: BizInfoCrawler
    public init(crawler: BizInfoCrawler = BizInfoCrawler()) { self.crawler = crawler }

    public struct LoadResult: Sendable {
        public let programs: [GovernmentProgram]
        public let usedSample: Bool
        public let note: String?

        public init(programs: [GovernmentProgram], usedSample: Bool, note: String?) {
            self.programs = programs
            self.usedSample = usedSample
            self.note = note
        }
    }

    /// crtfcKey 는 호환을 위해 받지만 사용하지 않는다(크롤링 기반).
    public func loadPrograms(
        crtfcKey: String = "",
        profile: ApplicantProfile = .blank,
        pages: Int = BizInfoEndpoints.defaultCrawlPages
    ) async -> LoadResult {
        guard SourceSiteGate.isEnabled(id: "bizinfo") else {
            return .init(programs: [], usedSample: false,
                         note: "출처 원장에서 기업마당이 꺼져 있다. government-support-source-sites enable --id bizinfo")
        }
        do {
            let got = try await crawler.crawl(pages: max(1, pages))
            if !got.isEmpty {
                return .init(programs: got, usedSample: false,
                             note: "기업마당 실시간 크롤링(\(got.count)건)")
            }
        } catch {
            return .init(programs: GovernmentProgram.sample, usedSample: true,
                         note: "기업마당 크롤링 실패 — 샘플([예시]) 표시. \(error.localizedDescription)")
        }
        return .init(programs: GovernmentProgram.sample, usedSample: true,
                     note: "기업마당 응답이 비었습니다 — 샘플([예시]) 표시.")
    }
}

public struct SubsidyLookupService: Sendable {
    public init() {}

    public struct LoadResult: Sendable {
        public let programs: [SubsidyProgram]
        public let note: String?

        public init(programs: [SubsidyProgram], note: String?) {
            self.programs = programs
            self.note = note
        }
    }

    public func loadPrograms(profile: ApplicantProfile = .blank) async -> LoadResult {
        .init(programs: SubsidyProgram.catalog, note: nil)
    }
}

public struct LoanLookupService: Sendable {
    public init() {}

    public struct LoadResult: Sendable {
        public let programs: [LoanProduct]
        public let note: String?

        public init(programs: [LoanProduct], note: String?) {
            self.programs = programs
            self.note = note
        }
    }

    public func loadPrograms(profile: ApplicantProfile = .blank) async -> LoadResult {
        .init(programs: LoanProduct.catalog, note: nil)
    }
}

public struct TaxBenefitLookupService: Sendable {
    public init() {}

    public struct LoadResult: Sendable {
        public let programs: [TaxBenefit]
        public let note: String?

        public init(programs: [TaxBenefit], note: String?) {
            self.programs = programs
            self.note = note
        }
    }

    public func loadPrograms(profile: ApplicantProfile = .blank) async -> LoadResult {
        .init(programs: TaxBenefit.catalog, note: nil)
    }
}
