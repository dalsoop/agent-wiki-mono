import Foundation
import WikiLedgerKit

// 기록 목록 표시 모델 — 현행 기록, 전신 포함 검색(전신 결과는 `[전신 <원장>]`), 4종류·유형 거르기.
// 검색은 CLI `search` 와 같은 엔진 함수(`LawScopedSearch`)를 쓴다.
// 근거: docs/business-rules.md "전신"(검색 범위·전신 표시)·"사실인정과 4종류"·"유형"(지식 기록).

public struct LawRecordListFilter: Sendable, Equatable {
    /// 비면 현행 기록 목록, 있으면 범위 검색.
    public var query: String
    public var memoryKind: LawMemoryKind?
    /// 지식 기록 유형(record·article·judgment) 하나로 거르기.
    public var type: LawRecordType?
    /// 검색에 전신 원장 결과를 넣을지.
    public var includePredecessors: Bool
    public var limit: Int

    public init(
        query: String = "", memoryKind: LawMemoryKind? = nil, type: LawRecordType? = nil,
        includePredecessors: Bool = true, limit: Int = 200
    ) {
        self.query = query
        self.memoryKind = memoryKind
        self.type = type
        self.includePredecessors = includePredecessors
        self.limit = limit
    }
}

public struct LawRecordListRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String?
    public let type: String?
    public let world: String
    public let isPredecessor: Bool
    /// `[전신 <원장>]`·`[상위 <원장>]`, 같은 원장이면 빈 문자열.
    public let scopeMark: String
    /// ledger 3 `record` 의 4종류(그 밖은 nil).
    public let memoryKind: LawMemoryKind?
    public let promulgated: Date
    public let author: String
    /// 검색 점수(목록이면 nil).
    public let score: Int?
}

public enum LawRecordList {
    /// 목록에 싣는 유형 — 지식 기록. 처리 기록은 목차·심급·드리밍 화면이 보인다.
    public static let listedTypes: [LawRecordType] = [.record, .article, .judgment]

    public static func rows(index: LawScopeIndex, filter: LawRecordListFilter) -> [LawRecordListRow] {
        var views: [String: LawLedgerView] = [:]
        func view(of world: String) -> LawLedgerView {
            if let cached = views[world] { return cached }
            let records = index.objects.filter { $0.world == world }
                .compactMap { item in item.law.map { LawStoredRecord(id: item.id, record: $0) } }
            let built = LawLedgerView(records: records)
            views[world] = built
            return built
        }
        func row(_ item: LawScopeObject, score: Int?) -> LawRecordListRow {
            LawRecordListRow(
                id: item.id, title: item.object.title, type: item.law?.type ?? item.object.effectiveType, world: item.world,
                isPredecessor: item.isPredecessor, scopeMark: LawScopedSearch.mark(item, current: index.current),
                memoryKind: item.law == nil ? nil : view(of: item.world).memoryKind(of: item.id),
                promulgated: item.object.published, author: item.object.author, score: score)
        }
        func listed(_ item: LawScopeObject) -> Bool {
            // ledger 3 기록은 지식 기록만, 전신(ledger 2) 객체는 유형 거르기가 없을 때만.
            if let law = item.law {
                guard let type = law.type.flatMap(LawRecordType.init(rawValue:)), listedTypes.contains(type) else { return false }
                return filter.type.map { $0 == type } ?? true
            }
            return filter.type == nil
        }

        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result: [LawRecordListRow]
        if query.isEmpty {
            let current = view(of: index.current)
            result = index.currentObjects
                .filter { $0.law != nil && current.isInForce($0.id) && listed($0) }
                .sorted { ($0.object.published, $0.id) > ($1.object.published, $1.id) }
                .map { row($0, score: nil) }
        } else {
            let parsed = WorldScopedSearchParse(queryText: query, limit: Int.max)
            result = LawScopedSearch.hits(index: index, parsed: parsed)
                .filter { (filter.includePredecessors || !$0.item.isPredecessor) && listed($0.item) }
                .map { row($0.item, score: $0.score) }
        }
        if let kind = filter.memoryKind { result = result.filter { $0.memoryKind == kind } }
        return Array(result.prefix(max(0, filter.limit)))
    }

    /// 검색어 없는 목록 — 이 원장의 현행 지식 기록만(범위·전신 색인을 읽지 않는다). `rows(index:filter:)` 의 목록과 같은 줄.
    public static func currentRows(world: String, records: [LawStoredRecord], filter: LawRecordListFilter) -> [LawRecordListRow] {
        let view = LawLedgerView(records: records)
        var result = view.inForce.filter { stored in
            guard let type = stored.record.type.flatMap(LawRecordType.init(rawValue:)), listedTypes.contains(type) else {
                return false
            }
            return filter.type.map { $0 == type } ?? true
        }
        .sorted { ($0.record.promulgated, $0.id) > ($1.record.promulgated, $1.id) }
        .map { stored in
            LawRecordListRow(
                id: stored.id, title: stored.record.title, type: stored.record.type, world: world, isPredecessor: false,
                scopeMark: "", memoryKind: view.memoryKind(of: stored.id), promulgated: stored.record.promulgated,
                author: stored.record.author, score: nil)
        }
        if let kind = filter.memoryKind { result = result.filter { $0.memoryKind == kind } }
        return Array(result.prefix(max(0, filter.limit)))
    }

    /// 화면 목록. 검색어가 없으면 이 원장만 읽고, 있으면 범위(같은 원장·상위·전신)를 읽어 검색한다. 화면은 배경에서 부른다.
    public static func load(target: LawLedgerTarget, filter: LawRecordListFilter) -> [LawRecordListRow] {
        load(target: target, filter: filter, records: nil)
    }

    /// 이미 읽은 이 원장의 기록으로 만든다(검색어가 없을 때 쓴다).
    public static func load(
        target: LawLedgerTarget, filter: LawRecordListFilter, records: [LawStoredRecord]?
    ) -> [LawRecordListRow] {
        guard filter.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return rows(index: LawScopeIndex(current: target.worldName, catalog: target.catalog), filter: filter)
        }
        return currentRows(world: target.worldName, records: records ?? target.store.scan(), filter: filter)
    }
}
