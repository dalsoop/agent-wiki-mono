import Foundation
import WikiLedgerKit

// 다른 원장의 기록 상세 — 드리밍 묶음 기록·다른 원장 보고·정지 원인 기록·전신 검색 결과가 가리키는 기록.
// 지금 원장에 없으면 드리밍 대상 원장들 → 읽기 범위(같은 원장·상위·전신, 검색과 같은 `LawScopeIndex`) 순으로 찾는다.
// 읽기만 한다(쓰기 게이트·공포 경로와 무관). 화면은 상세의 `world` 가 지금 원장이 아니면 편집을 숨긴다.
// 근거: docs/business-rules.md "전신"(검색 범위)·"드리밍"(여러 원장 묶음).
extension LawRecordDetail {
    /// 이 원장의 기록(`records`)에서 먼저 찾고, 없으면 `otherLedgers`(이미 읽은 드리밍 대상 원장들) → 읽기 범위 순.
    /// 읽기 범위는 앞의 두 곳에서 못 찾았을 때만 읽는다.
    public static func load(
        id: String, target: LawLedgerTarget, records: [LawStoredRecord],
        otherLedgers: [(world: String, records: [LawStoredRecord])]
    ) -> LawRecordDetail? {
        if let local = load(id: id, target: target, records: records) { return local }
        for ledger in otherLedgers where ledger.world != target.worldName {
            if let other = target.reading(world: ledger.world),
               let detail = load(id: id, target: other, records: ledger.records) {
                return detail
            }
        }
        let index = LawScopeIndex(current: target.worldName, catalog: target.catalog)
        let matches = index.idMatches(id).filter { $0.world != target.worldName }
        guard matches.count == 1, let hit = matches.first, let other = target.reading(world: hit.world) else { return nil }
        let worldRecords = index.objects.filter { $0.world == hit.world }.map(storedRecord)
        return load(id: hit.id, target: other, records: worldRecords)
    }

    /// 범위 안 기록 하나를 상세용 기록으로. ledger 3 는 원 기록 그대로, 전신(ledger 2) 객체는 같은 칸만 옮긴 보기.
    static func storedRecord(_ item: LawScopeObject) -> LawStoredRecord {
        if let law = item.law { return LawStoredRecord(id: item.id, record: law) }
        let object = item.object
        return LawStoredRecord(id: object.id, record: LawRecord(
            ledger: object.ledger, promulgated: object.published, author: object.author,
            title: object.title, type: object.effectiveType, origin: object.origin, batch: object.batch,
            tags: object.tags,
            relations: LawRelations(
                cites: object.cites.map { LawCite(id: $0.id, rel: $0.rel) },
                amends: object.supersedes, amendsAlso: object.supersedesAlso, repeals: object.retracts),
            body: object.body))
    }
}

extension LawLedgerTarget {
    /// 같은 설정으로 다른 원장을 읽는 대상(상세 표시에만 쓴다). 설정에 없는 원장이면 nil.
    func reading(world: String) -> LawLedgerTarget? {
        guard let root = catalog.world(named: world)?.rootPath else { return nil }
        return LawLedgerTarget(
            worldName: world, root: URL(fileURLWithPath: root), catalog: catalog,
            registeredDevices: registeredDevices, currentDevice: currentDevice, file: file)
    }
}
