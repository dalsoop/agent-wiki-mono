import Foundation

/// UUIDv7 원장을 content-addressed(id = sha256 코어) 로 재주소화하는 순수 변환.
/// filter-repo 방식: 위상정렬로 참조 대상을 먼저 재해시한 뒤 참조를 remap 한다.
/// 원본을 안 건드리고 (old id → new id) 맵과 재직렬화 결과를 낸다 — 파일 I/O 는 호출측.
public struct LedgerMigration {
    public struct Migrated: Sendable {
        public let oldID: String
        public let newID: String
        public let published: Date
        public let serialized: String
        public let unchanged: Bool   // 이미 content-id 라 old==new
    }

    public struct Report: Sendable {
        public let remap: [String: String]   // old id → new id (무변경이면 old==new)
        public let migrated: [Migrated]       // dedup 후 유일한 새 객체들
        public let rounds: Int
        public let deduped: Int               // 재주소화 후 같은 해시로 합쳐진 수
        public let cycleForced: Int           // 교착(순환)으로 강제 처리된 수
        public var changed: Int { remap.reduce(0) { $0 + ($1.key == $1.value ? 0 : 1) } }
    }

    /// 입력 객체들을 content-addressed 로 재주소화. 이미 content-id 인 객체는 그대로 통과.
    public static func readdress(_ input: [LedgerObject]) -> Report {
        let objIDs = Set(input.map(\.id))
        let byID = Dictionary(input.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        func objectRefs(_ object: LedgerObject) -> [String] {
            (object.cites.map(\.id) + [object.supersedes, object.retracts].compactMap { $0 })
                .filter { objIDs.contains($0) }
        }

        var remap: [String: String] = [:]
        var migrated: [Migrated] = []
        var seenNew: Set<String> = []
        var pending = Set(input.map(\.id))
        var rounds = 0, cycleForced = 0, deduped = 0

        while !pending.isEmpty {
            rounds += 1
            var ready = pending.filter { objectRefs(byID[$0]!).allSatisfy { remap[$0] != nil } }
            if ready.isEmpty {                 // 교착(순환) — append-only 원장엔 정상적으로 없음
                cycleForced += pending.count
                ready = pending                // 강제 처리(참조는 old id 로 남음)
            }
            for oldID in ready {
                let object = byID[oldID]!
                let newCites = object.cites.map {
                    LedgerObject.Cite(id: remap[$0.id] ?? $0.id, rel: $0.rel)
                }
                let newSupersedes = object.supersedes.map { remap[$0] ?? $0 }
                let newRetracts = object.retracts.map { remap[$0] ?? $0 }
                func build(id: String) -> LedgerObject {
                    LedgerObject(id: id, published: object.published, author: object.author, title: object.title, type: object.type, body: object.body, extras: LedgerObject.Extras(batch: object.batch, origin: object.origin, tags: object.tags, cites: newCites, observes: object.observes, supersedes: newSupersedes, retracts: newRetracts, source: object.source, unknownFields: object.unknownFields))
                }
                let newID = build(id: "").contentID()
                remap[oldID] = newID
                if seenNew.contains(newID) {
                    deduped += 1
                } else {
                    seenNew.insert(newID)
                    migrated.append(Migrated(
                        oldID: oldID, newID: newID, published: object.published,
                        serialized: build(id: newID).serialize(),
                        unchanged: oldID == newID))
                }
                pending.remove(oldID)
            }
        }
        return Report(remap: remap, migrated: migrated, rounds: rounds,
                      deduped: deduped, cycleForced: cycleForced)
    }
}
