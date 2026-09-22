import Foundation
import StateRootKit

public struct BacklogAppSummary: Identifiable, Equatable, Sendable {
    public var id: String { slug }
    public let slug: String
    public let openCount: Int
    public let defectCount: Int
    public let p0DefectCount: Int
    public let totalCount: Int

    public init(
        slug: String,
        openCount: Int,
        defectCount: Int,
        p0DefectCount: Int,
        totalCount: Int
    ) {
        self.slug = slug
        self.openCount = openCount
        self.defectCount = defectCount
        self.p0DefectCount = p0DefectCount
        self.totalCount = totalCount
    }
}

public struct BacklogStore: Sendable {
    public static var defaultPortfolioRoot: URL {
        StateRootKit.url(".product-portfolio")
    }

    public let portfolioRoot: URL

    public init(portfolioRoot: URL = Self.defaultPortfolioRoot) {
        self.portfolioRoot = portfolioRoot
    }

    public var backlogRoot: URL {
        portfolioRoot.appendingPathComponent("backlog", isDirectory: true)
    }

    @discardableResult
    public func add(
        slug: String,
        title: String,
        description: String,
        source: String,
        kind: BacklogKind? = nil,
        priority: BacklogPriority = .p2,
        impact: Int = 3,
        effort: Int = 0
    ) throws -> BacklogItem {
        try insert(BacklogItem(
            content: .init(
                slug: slug,
                title: title,
                description: description,
                source: source,
                kind: kind
            ),
            scoring: .init(priority: priority, impact: impact, effort: effort)
        ))
    }

    @discardableResult
    public func insert(_ item: BacklogItem) throws -> BacklogItem {
        let url = fileURL(for: item.id)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw BacklogError.alreadyExists(item.id)
        }
        try write(item)
        return item
    }

    public func show(id: UUID) throws -> BacklogItem {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BacklogError.notFound(id)
        }
        return try loadFile(url)
    }

    public func list(
        status: BacklogStatus? = nil,
        product: String? = nil,
        kind: BacklogKind? = nil,
        claimedBy: String? = nil
    ) throws -> [BacklogItem] {
        guard FileManager.default.fileExists(atPath: backlogRoot.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: backlogRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try urls
            .filter { $0.pathExtension == "json" }
            .map(loadFile)
            .filter { status == nil || $0.status == status }
            .filter { product == nil || $0.slug == product }
            .filter { kind == nil || $0.kind == kind }
            .filter { claimedBy == nil || $0.claimedBy == claimedBy }
            .sorted(by: Self.sortBefore)
    }

    public func listAppSummaries(includeDone: Bool = false) throws -> [BacklogAppSummary] {
        let allItems = try list()
        let grouped = Dictionary(grouping: allItems, by: { $0.slug })
        var summaries: [BacklogAppSummary] = []

        for (slug, items) in grouped {
            let openItems = items.filter { $0.status != .done && $0.status != .dropped }
            let openCount = openItems.count
            let defectCount = items.filter { $0.kind == .defect }.count
            let p0DefectCount = openItems.filter { $0.kind == .defect && $0.priority == .p0 }.count

            if includeDone || openCount > 0 {
                summaries.append(BacklogAppSummary(
                    slug: slug,
                    openCount: openCount,
                    defectCount: defectCount,
                    p0DefectCount: p0DefectCount,
                    totalCount: items.count
                ))
            }
        }

        return summaries.sorted { lhs, rhs in
            if lhs.openCount != rhs.openCount {
                return lhs.openCount > rhs.openCount
            }
            return lhs.slug < rhs.slug
        }
    }

    @discardableResult
    public func promote(id: UUID, priority: BacklogPriority) throws -> BacklogItem {
        let item = try show(id: id)
        let nextStatus: BacklogStatus = item.status == .candidate ? .planned : item.status
        let updated = try item.replacing(priority: priority, status: nextStatus)
        try write(updated)
        return updated
    }

    /// 상태를 바꾼다. `in-progress` 로 올릴 때는 **점유자를 같이 남긴다** — 그래야
    /// 다른 세션이 "누가 하고 있나" 를 볼 수 있다. 이미 다른 에이전트가 살아 있는
    /// 점유를 들고 있으면 거절한다(강행은 force).
    ///
    /// done/dropped 로 끝나면 점유를 푼다 — 끝난 일을 계속 붙잡고 있을 이유가 없다.
    @discardableResult
    public func updateStatus(
        id: UUID, status: BacklogStatus, agent: String? = nil, force: Bool = false,
        now: Date = Date()
    ) throws -> BacklogItem {
        let item = try show(id: id)
        var claim: BacklogItem.Claim?
        switch status {
        case .inProgress:
            if let agent {
                if let holder = item.claimedBy, holder != agent, item.claimIsActive(now: now), !force {
                    throw BacklogError.claimed(id: id, by: holder, at: item.claimedAt ?? now)
                }
                claim = .init(owner: agent, at: now)
            }
        case .done, .dropped:
            claim = .release
        case .candidate, .planned:
            // 다시 대기열로 돌아가면 아무도 안 붙잡고 있는 상태가 맞다
            // (AWO 가 실패 잡의 백로그를 planned 로 되돌릴 때 여기로 온다).
            claim = .release
        }
        let updated = try item.replacing(status: status, claim: claim)
        try write(updated)
        return updated
    }

    /// 상태를 안 바꾸고 점유만 잡는다.
    @discardableResult
    public func claim(id: UUID, agent: String, force: Bool = false, now: Date = Date()) throws -> BacklogItem {
        let item = try show(id: id)
        if let holder = item.claimedBy, holder != agent, item.claimIsActive(now: now), !force {
            throw BacklogError.claimed(id: id, by: holder, at: item.claimedAt ?? now)
        }
        let updated = try item.replacing(claim: .init(owner: agent, at: now))
        try write(updated)
        return updated
    }

    @discardableResult
    public func release(id: UUID) throws -> BacklogItem {
        let updated = try show(id: id).replacing(claim: .release)
        try write(updated)
        return updated
    }

    public func importCandidates() throws -> ImportSummary {
        var existing = try list()
        var imported = 0
        var skipped = 0

        for candidate in try feedbackCandidates() + evaluationCandidates() {
            if existing.contains(where: { Self.isDuplicate($0, candidate) }) {
                skipped += 1
                continue
            }
            try write(candidate)
            existing.append(candidate)
            imported += 1
        }
        return ImportSummary(imported: imported, skipped: skipped)
    }

    private func fileURL(for id: UUID) -> URL {
        backlogRoot.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    private func write(_ item: BacklogItem) throws {
        try FileManager.default.createDirectory(at: backlogRoot, withIntermediateDirectories: true)
        try BacklogCodec.encode(item).write(to: fileURL(for: item.id), options: .atomic)
    }

    private func loadFile(_ url: URL) throws -> BacklogItem {
        do {
            return try BacklogCodec.decode(BacklogItem.self, from: Data(contentsOf: url))
        } catch {
            throw BacklogError.invalidData(url.lastPathComponent)
        }
    }

    private static func sortBefore(_ lhs: BacklogItem, _ rhs: BacklogItem) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        if lhs.impact != rhs.impact { return lhs.impact > rhs.impact }
        if lhs.effort != rhs.effort { return lhs.effort < rhs.effort }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func isDuplicate(_ existing: BacklogItem, _ candidate: BacklogItem) -> Bool {
        guard existing.source == candidate.source else { return false }
        if candidate.source.hasPrefix("feedback:") { return true }
        return existing.title.localizedCaseInsensitiveCompare(candidate.title) == .orderedSame
    }
}

private extension BacklogStore {
    struct FeedbackCandidate: Decodable {
        let id: UUID
        let slug: String
        let text: String
        let featureCandidate: Bool
    }

    struct EvaluationCandidate: Decodable {
        let slug: String
        let improvements: [ImprovementCandidate]
    }

    struct EvaluationDocumentCandidate: Decodable {
        let current: EvaluationCandidate
    }

    struct ImprovementCandidate: Decodable {
        let text: String
        let severity: String?
        let suggestedAction: String?
    }

    func feedbackCandidates() throws -> [BacklogItem] {
        let root = portfolioRoot.appendingPathComponent("feedback", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try jsonFiles(at: root).compactMap { url in
            let value: FeedbackCandidate
            do {
                value = try JSONDecoder().decode(FeedbackCandidate.self, from: Data(contentsOf: url))
            } catch {
                throw BacklogError.invalidData("feedback/\(url.lastPathComponent)")
            }
            guard value.featureCandidate else { return nil }
            return try BacklogItem(
                content: .init(
                    slug: value.slug,
                    title: value.text,
                    description: value.text,
                    source: "feedback:\(value.id.uuidString.lowercased())"
                ),
                scoring: .init(priority: .p2, impact: 3, effort: 0)
            )
        }
    }

    func evaluationCandidates() throws -> [BacklogItem] {
        let root = portfolioRoot.appendingPathComponent("evaluations", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try jsonFiles(at: root).flatMap { url -> [BacklogItem] in
            let data = try Data(contentsOf: url)
            let evaluation: EvaluationCandidate
            do {
                do {
                    evaluation = try JSONDecoder().decode(EvaluationDocumentCandidate.self, from: data).current
                } catch {
                    evaluation = try JSONDecoder().decode(EvaluationCandidate.self, from: data)
                }
            } catch {
                throw BacklogError.invalidData("evaluations/\(url.lastPathComponent)")
            }
            return try evaluation.improvements.map { improvement in
                let mapped = priorityAndImpact(for: improvement.severity)
                return try BacklogItem(
                    content: .init(
                        slug: evaluation.slug,
                        title: improvement.text,
                        description: improvement.suggestedAction ?? improvement.text,
                        source: "evaluation:\(evaluation.slug)"
                    ),
                    scoring: .init(priority: mapped.priority, impact: mapped.impact, effort: 0)
                )
            }
        }
    }

    func jsonFiles(at root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func priorityAndImpact(for severity: String?) -> (priority: BacklogPriority, impact: Int) {
        switch severity?.lowercased() {
        case "critical": (.p0, 5)
        case "high": (.p1, 4)
        case "low": (.p3, 2)
        default: (.p2, 3)
        }
    }
}
