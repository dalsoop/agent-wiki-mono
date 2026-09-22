import Foundation

/// 도메인 중립 기회/공고/딜 중복제거 및 클러스터링 엔진
/// 동일 기관/제공자 + 유사 제목/URL을 기반으로 중복 항목을 군집화하고
/// 최신 마감일 및 최고 지원금을 보존하여 단일 대표 항목으로 병합한다.
public enum OpportunityDedupEngine {

    public struct DedupResult: Sendable, Equatable {
        /// 중복 제거 및 병합이 완료된 고유 항목 목록
        public var items: [OpportunityIntelItem]
        /// 흡수/병합되어 제거된 중복 항목 수
        public var mergedCount: Int
        /// 식별된 클러스터 상세 목록
        public var clusters: [OpportunityCluster]

        public init(
            items: [OpportunityIntelItem] = [],
            mergedCount: Int = 0,
            clusters: [OpportunityCluster] = []
        ) {
            self.items = items
            self.mergedCount = mergedCount
            self.clusters = clusters
        }
    }

    public struct OpportunityCluster: Sendable, Equatable {
        public var canonicalKey: String
        public var items: [OpportunityIntelItem]
        public var mergedItem: OpportunityIntelItem

        public init(canonicalKey: String, items: [OpportunityIntelItem], mergedItem: OpportunityIntelItem) {
            self.canonicalKey = canonicalKey
            self.items = items
            self.mergedItem = mergedItem
        }
    }

    // MARK: - Public API

    /// 기회 항목 목록에서 중복을 식별하여 병합된 고유 항목 목록만 반환한다.
    public static func deduplicate(_ items: [OpportunityIntelItem]) -> [OpportunityIntelItem] {
        return clusterAndMerge(items).items
    }

    /// 기회 항목 목록을 클러스터링하고 병합 결과 상세를 반환한다.
    public static func clusterAndMerge(_ items: [OpportunityIntelItem]) -> DedupResult {
        guard !items.isEmpty else {
            return DedupResult()
        }

        let n = items.count
        var parent = Array(0..<n)

        func find(_ x: Int) -> Int {
            var r = x
            while parent[r] != r {
                r = parent[r]
            }
            var curr = x
            while curr != r {
                let nxt = parent[curr]
                parent[curr] = r
                curr = nxt
            }
            return r
        }

        func union(_ a: Int, _ b: Int) {
            let rootA = find(a)
            let rootB = find(b)
            if rootA != rootB {
                parent[rootB] = rootA
            }
        }

        // 1. 쌍별 중복 여부 판정 (Union-Find)
        for i in 0..<n {
            for j in (i + 1)..<n {
                if areDuplicates(items[i], items[j]) {
                    union(i, j)
                }
            }
        }

        // 2. 루트별 클러스터 그룹핑
        var groups: [Int: [OpportunityIntelItem]] = [:]
        for i in 0..<n {
            let root = find(i)
            groups[root, default: []].append(items[i])
        }

        // 3. 결정적 순서 유지를 위한 정렬 (입력 순서 기준)
        let sortedRoots = groups.keys.sorted()
        var clusters: [OpportunityCluster] = []
        var mergedItems: [OpportunityIntelItem] = []

        for root in sortedRoots {
            let clusterItems = groups[root] ?? []
            let merged = merge(cluster: clusterItems)
            let cluster = OpportunityCluster(
                canonicalKey: items[root].id,
                items: clusterItems,
                mergedItem: merged
            )
            clusters.append(cluster)
            mergedItems.append(merged)
        }

        return DedupResult(
            items: mergedItems,
            mergedCount: items.count - mergedItems.count,
            clusters: clusters
        )
    }

    /// 두 항목이 동일한 공고/딜 기회인지 여부를 판별한다.
    public static func areDuplicates(_ a: OpportunityIntelItem, _ b: OpportunityIntelItem) -> Bool {
        if isMatchingNormalizedURL(a: a, b: b) { return true }
        guard isSameProvider(a, b) else { return false }
        return isMatchingTitleOrURL(a: a, b: b)
    }

    private static func isMatchingNormalizedURL(a: OpportunityIntelItem, b: OpportunityIntelItem) -> Bool {
        let normUrlA = normalizeURL(a.url)
        let normUrlB = normalizeURL(b.url)
        return !normUrlA.isEmpty && normUrlA == normUrlB
    }

    private static func isMatchingTitleOrURL(a: OpportunityIntelItem, b: OpportunityIntelItem) -> Bool {
        if isSimilarTitle(a.title, b.title) { return true }
        return isSimilarURL(a.url, b.url)
    }

    /// 두 항목을 단일 항목으로 병합한다 (최신 마감일 및 최고 지원금 보존).
    public static func merge(_ a: OpportunityIntelItem, _ b: OpportunityIntelItem) -> OpportunityIntelItem {
        return merge(cluster: [a, b])
    }

    /// 단일 클러스터 내의 모든 항목을 하나로 병합한다.
    public static func merge(cluster: [OpportunityIntelItem]) -> OpportunityIntelItem {
        guard let primary = cluster.first else {
            return OpportunityIntelItem(
                id: "empty", provider: "", canonical: "", title: "", summary: "",
                url: "", category: ""
            )
        }
        if cluster.count == 1 {
            return primary
        }

        // 1. 최신 마감일 보존 (가장 늦은 마감일 선정)
        var latestDeadline: String? = nil
        for item in cluster {
            latestDeadline = selectLatestDeadline(between: latestDeadline, and: item.deadline)
        }

        // 2. 최고 지원금 보존 (실부담금/지원금/정가 중 최대치 보유 항목의 값 선정)
        let bestGrantItem = cluster.max { item1, item2 in
            extractMaxGrantValue(from: item1) < extractMaxGrantValue(from: item2)
        } ?? primary

        // 최고 지원율 / 할인율 보존
        let highestRate = cluster.compactMap { $0.discountOrSupportRate }.max()

        // 3. 최초 발견일(min) 및 최종 확인일(max) 보존
        let minFirstSeen = cluster.map { $0.firstSeen }.filter { !$0.isEmpty }.min() ?? primary.firstSeen
        let maxLastSeen = cluster.map { $0.lastSeen }.filter { !$0.isEmpty }.max() ?? primary.lastSeen

        // 4. 생존 상태 보존 (alive > caution > expired > dead)
        let bestLiveness = selectBestLiveness(from: cluster.map { $0.liveness })

        // 5. 점수 보존 (최고점)
        let maxScore = cluster.map { $0.score }.max() ?? primary.score

        // 6. 태그 통합 (합집합)
        var combinedTags: [String] = []
        for item in cluster {
            for tag in item.tags {
                if !combinedTags.contains(tag) {
                    combinedTags.append(tag)
                }
            }
        }

        // 7. 자부담 비율 및 모집 대상 보존
        let bestSelfPay = cluster.compactMap { $0.selfPayRatio }.first(where: { !$0.isEmpty }) ?? primary.selfPayRatio
        let bestAudience = cluster.compactMap { $0.targetAudience }.first(where: { !$0.isEmpty }) ?? primary.targetAudience

        // 8. 요약 및 자격요건 (가장 상세한 내용 선정)
        let richestSummary = cluster.map { $0.summary }.max(by: { $0.count < $1.count }) ?? primary.summary
        let richestPrereq = cluster.compactMap { $0.prerequisites }.max(by: { $0.count < $1.count }) ?? primary.prerequisites
        let bestCode = cluster.compactMap { $0.opportunityCode }.first(where: { !$0.isEmpty }) ?? primary.opportunityCode

        return OpportunityIntelItem(
            id: primary.id,
            provider: primary.provider,
            canonical: primary.canonical,
            title: primary.title,
            summary: richestSummary,
            url: primary.url,
            category: primary.category,
            standardValue: bestGrantItem.standardValue ?? primary.standardValue,
            actualValue: bestGrantItem.actualValue ?? primary.actualValue,
            discountOrSupportRate: highestRate,
            opportunityCode: bestCode,
            deadline: latestDeadline,
            prerequisites: richestPrereq,
            selfPayRatio: bestSelfPay,
            targetAudience: bestAudience,
            score: maxScore,
            liveness: bestLiveness,
            firstSeen: minFirstSeen,
            lastSeen: maxLastSeen,
            tags: combinedTags
        )
    }

    private static func selectBestLiveness(from states: [OpportunityLiveness]) -> OpportunityLiveness {
        let priorityOrder: [OpportunityLiveness] = [.alive, .caution, .expired, .dead]
        return priorityOrder.first(where: { states.contains($0) }) ?? .dead
    }
}
