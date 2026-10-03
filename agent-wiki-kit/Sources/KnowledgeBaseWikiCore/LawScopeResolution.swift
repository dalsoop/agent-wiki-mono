import Foundation
import WikiLedgerKit

// 원장 계층의 읽기 범위(같은 원장·상위 사슬·그 각각의 전신)를 형식에 맞게 읽는다.
// 범위는 `WorldSearchScope.entries` 가 정하고, 범위 밖 참조의 판정 문구는 `WorldCiteGate` 가 낸다.
// 근거: docs/business-rules.md "전신", docs/security.md "agent-law 격리", 결정 0007.

/// 범위 안의 기록 하나(형식과 무관한 투영 + ledger 3 원문).
public struct LawScopeObject: Sendable {
    public let world: String
    public let entry: WorldScopeEntry
    public let object: LedgerObject
    /// ledger 3 원장의 기록이면 원 기록.
    public let law: LawRecord?

    public var id: String { object.id }
    public var isPredecessor: Bool { entry.predecessor }
}

public enum LawWorldReader {
    /// world 하나의 기록을 그 형식대로 읽어 투영한다. ledger 3 판정은 설정(`isLedgerThree`) 하나로 한다.
    public static func objects(world: BoundWorld, catalog: WorldBindingCatalog) -> [(LedgerObject, LawRecord?)] {
        let root = URL(fileURLWithPath: world.rootPath)
        if catalog.isLedgerThree(world.name) {
            return LawStore(root: root).scan().map { (LawLedgerProjection.object($0), $0.record) }
        }
        return LedgerStore(root: root).scan().map { ($0, nil) }
    }

    /// 모든 등록 world 의 id 집합(형식별로 읽음). 인용 게이트의 world 찾기에 쓴다.
    public static func idsByWorld(catalog: WorldBindingCatalog) -> [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        for world in catalog.worlds {
            map[world.name] = Set(objects(world: world, catalog: catalog).map(\.0.id))
        }
        return map
    }
}

/// 현재 원장의 읽기 범위 전체를 한 번 읽어 둔 것.
public struct LawScopeIndex: Sendable {
    public let current: String
    public let catalog: WorldBindingCatalog
    public let entries: [WorldScopeEntry]
    public let objects: [LawScopeObject]
    private let byID: [String: LawScopeObject]

    public init(current: String, catalog: WorldBindingCatalog) {
        self.current = current
        self.catalog = catalog
        let entries = WorldSearchScope.entries(current: current, catalog: catalog)
        self.entries = entries
        var collected: [LawScopeObject] = []
        for entry in entries {
            guard let world = catalog.world(named: entry.name) else { continue }
            for (object, law) in LawWorldReader.objects(world: world, catalog: catalog) {
                collected.append(LawScopeObject(world: entry.name, entry: entry, object: object, law: law))
            }
        }
        objects = collected
        var map: [String: LawScopeObject] = [:]
        for item in collected where map[item.id] == nil { map[item.id] = item }
        byID = map
    }

    public func object(id: String) -> LawScopeObject? { byID[id] }

    /// 현재 원장의 기록만.
    public var currentObjects: [LawScopeObject] { objects.filter { $0.world == current } }

    /// 참조 토큰(64자 id 또는 유일한 id 접두어 4자 이상) → 범위 안 기록들.
    public func idMatches(_ token: String) -> [LawScopeObject] {
        let key = token.trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = byID[key] { return [exact] }
        guard key.count >= 4 else { return [] }
        return uniqueByID(objects.filter { $0.id.hasPrefix(key) })
    }

    /// 조회 토큰 해석 — id 접두·일치 → 제목 정확 일치 → alias 태그 → 제목 접두 → 제목 부분 일치.
    /// 현재 원장의 결과가 있으면 그것을 먼저 쓴다.
    public func lookup(_ token: String) -> [LawScopeObject] {
        let ids = idMatches(token)
        if !ids.isEmpty { return ids }
        let needle = token.precomposedStringWithCanonicalMapping
        let stages: [(LawScopeObject) -> Bool] = [
            { ($0.object.title ?? "").precomposedStringWithCanonicalMapping == needle },
            { $0.object.tags.contains("alias:\(needle)") },
            { ($0.object.title ?? "").precomposedStringWithCanonicalMapping.hasPrefix(needle) },
            { ($0.object.title ?? "").precomposedStringWithCanonicalMapping.contains(needle) },
        ]
        for stage in stages {
            let hits = uniqueByID(objects.filter(stage))
            if hits.isEmpty { continue }
            let local = hits.filter { $0.world == current }
            return local.isEmpty ? hits : local
        }
        return []
    }

    private func uniqueByID(_ items: [LawScopeObject]) -> [LawScopeObject] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }
    }
}

/// 공포·감사에 넣는 참조 해석기 — 범위(같은 원장·상위·전신) 안의 기록만 푼다.
/// 전신 객체(ledger 2)는 그 유형(명시 type, 없으면 제목 접두어 유도)·출처를 가능한 만큼 싣는다.
public struct LawScopeReferenceResolver: LawReferenceResolving {
    private let references: [String: LawResolvedReference]

    public init(index: LawScopeIndex) {
        var map: [String: LawResolvedReference] = [:]
        for item in index.objects where map[item.id] == nil {
            let scope: LawReferenceScope = item.world == index.current
                ? .sameLedger : (item.isPredecessor ? .predecessor : .ancestor)
            map[item.id] = LawResolvedReference(
                id: item.id,
                type: item.law?.type ?? item.object.effectiveType,
                origin: item.law?.origin ?? item.object.origin,
                speaker: item.law?.speaker,
                scope: scope)
        }
        references = map
    }

    public func resolve(_ id: String) -> LawResolvedReference? { references[id] }
}

/// 참조 토큰 해석 실패.
public enum LawReferenceError: Error, Equatable, CustomStringConvertible {
    case missing(String)
    case ambiguous(String, [String])
    case outOfScope(WorldCiteDenial)

    public var description: String {
        switch self {
        case .missing(let token): return "없는 기록 참조: \(token)"
        case .ambiguous(let token, let ids):
            let sample = ids.prefix(10).map { "  " + String($0.prefix(12)) }.joined(separator: "\n")
            return "여러 개 매칭(\(ids.count)건) — 더 좁혀 주세요: \(token)\n\(sample)"
        case .outOfScope(let denial): return denial.message
        }
    }
}

public enum LawReferenceLookup {
    /// 참조 토큰 → 범위 안의 64자 id. 범위 밖 world 에 있으면 인용 게이트(`WorldCiteGate`)의 거부를 낸다.
    public static func resolve(_ token: String, index: LawScopeIndex) throws -> String {
        let matches = index.idMatches(token)
        if matches.count == 1 { return matches[0].id }
        if matches.count > 1 { throw LawReferenceError.ambiguous(token, matches.map(\.id)) }
        let located = LawWorldReader.idsByWorld(catalog: index.catalog)
        if let world = WorldCiteGate.locateWorld(containing: token, objectsByWorld: located),
           let denial = WorldCiteGate.evaluate(
            currentWorld: index.current, citedID: token, citedWorld: world, catalog: index.catalog) {
            throw LawReferenceError.outOfScope(denial)
        }
        throw LawReferenceError.missing(token)
    }
}
