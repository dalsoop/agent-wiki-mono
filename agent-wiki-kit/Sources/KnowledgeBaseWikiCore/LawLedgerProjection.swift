import Foundation
import WikiLedgerKit

/// ledger 3 기록을 조회·색인용 `LedgerObject` 로 비추는 읽기 전용 투영.
/// 쓰지 않는다 — 원장 파일의 정본은 ledger 3 기록이고, 투영은 검색·색인·그래프·화면 목록이
/// 옛 형식과 같은 자리에서 ledger 3 를 읽게 하는 연결일 뿐이다(`amends` → supersedes,
/// `amends-also` → supersedes-also, `repeals` → retracts, `promulgated` → published).
/// 근거: docs/contracts.md "agent-law 명령"(조회 명령은 이름과 뜻을 유지), 결정 0007.
public enum LawLedgerProjection {
    public static func object(_ stored: LawStoredRecord) -> LedgerObject {
        let record = stored.record
        return LedgerObject(
            id: stored.id,
            published: record.promulgated,
            author: record.author,
            title: record.title,
            type: record.type,
            body: record.body,
            extras: LedgerObject.Extras(
                batch: record.batch,
                origin: record.origin,
                tags: record.tags,
                cites: record.cites.map { LedgerObject.Cite(id: $0.id, rel: $0.rel) },
                supersedes: record.amends,
                retracts: record.repeals,
                ledger: LawRecord.ledgerVersion,
                supersedesAlso: record.amendsAlso))
    }

    /// ledger 3 파일 원문 → 투영. ledger 3 가 아니면 nil.
    public static func object(fromText text: String) -> LedgerObject? {
        guard let parsed = LawRecordParser.parse(text) else { return nil }
        return object(LawStoredRecord(id: parsed.storedID, record: parsed.record))
    }

    public static func objects(_ records: [LawStoredRecord]) -> [LedgerObject] {
        records.map(object)
    }
}
