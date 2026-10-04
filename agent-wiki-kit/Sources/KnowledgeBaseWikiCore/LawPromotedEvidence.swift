import Foundation
import WikiLedgerKit

// 승격된 증거의 증언 — 공유 원장 기록이 사용자 증언을 갖는 길.
// 개인·테넌트 원장에서 증언을 확인한 증거 기록을 `promote` 로 공유 원장에 올린다. 승격할 때 원본 원장의
// 범위에서 증언을 다시 확인하고(`LawPromotionTestimony.reverify`), 대상 원장의 승격본은 그 결과로 공포된다.
// 그 뒤 승격본의 화자는 승격 영수증이 증언 확인을 대신한다(`LawPromotionWitness`).
// - 대상 쪽 표지: 대상 원장의 `promotion-receipt` 기록(승격본을 `receipts` 로 인용, 본문 = 영수증 JSON)과
//   승격본의 `promoted` 태그. 코어 필드·관계 집합·머리 칸은 바꾸지 않는다.
// - 확인: 표지만으로는 통과하지 않는다. 영수증 본문의 원본 원장(대상의 하위 원장, 설정의 루트와 같은 자리)을
//   감사·검증 목적으로 읽어, 같은 영수증 본문의 원본 영수증(`receipts` → 원본, `promoted-as` → 승격본)과
//   코어가 온전한 원본 증거 기록(화자·증거물·본문 일치)을 실제로 찾을 때만 승격본으로 인정한다.
//   옛 승격 검증기(`PromotionVerifier`)가 영수증의 원본 world 를 읽는 방식과 같다.
// 근거: docs/business-rules.md "화자"(2026-10-04 사용자 결정 "개인에서 확인한 증거를 승격")·"관계",
// docs/contracts.md "승격", docs/security.md "agent-law" 격리 표.

/// 승격본 주장의 판정.
public enum LawPromotedEvidenceStatus: Sendable, Equatable {
    /// 승격본이라고 주장하지 않는 기록(일반 증거·다른 유형).
    case notClaimed
    /// 원본 원장의 영수증과 원본 증거로 확인된 승격본.
    case genuine
    /// 승격본이라고 주장하지만 확인되지 않음(이유).
    case unproven(String)
}

/// 승격본 확인자 — 인용 검증(`testifies`)과 감사가 쓴다.
public protocol LawPromotedEvidenceVerifying: Sendable {
    func status(of id: String) -> LawPromotedEvidenceStatus
}

public struct LawPromotionWitness: LawPromotedEvidenceVerifying {
    static let promotedTag = "promoted"

    struct Entry: Sendable {
        let world: String?
        let record: LawRecord
    }

    private let records: [String: Entry]
    /// 승격본 id → 그것을 `receipts` 로 인용하는 대상 영수증들.
    private let targetReceipts: [String: [Entry]]
    /// 원본 원장을 찾는 설정. 없으면 승격본을 확인할 수 없다(주장은 모두 미확인).
    private let catalog: WorldBindingCatalog?

    /// 읽기 범위(같은 원장·상위 사슬) 전체에서.
    public init(index: LawScopeIndex) {
        self.init(
            entries: index.objects.compactMap { item in item.law.map { (item.id, Entry(world: item.world, record: $0)) } },
            catalog: index.catalog)
    }

    /// 같은 원장의 기록만(설정 없음) — 주입되지 않은 문맥의 기본값. 승격본 주장을 확인하지 못한다.
    public init(records: [LawStoredRecord]) {
        self.init(entries: records.map { ($0.id, Entry(world: nil, record: $0.record)) }, catalog: nil)
    }

    init(entries: [(String, Entry)], catalog: WorldBindingCatalog?) {
        var byID: [String: Entry] = [:]
        var receipts: [String: [Entry]] = [:]
        for (id, entry) in entries {
            if byID[id] == nil { byID[id] = entry }
            guard entry.record.type == LawRecordType.promotionReceipt.rawValue else { continue }
            for cite in entry.record.cites where cite.rel == LawRelation.receipts.rawValue {
                receipts[cite.id, default: []].append(entry)
            }
        }
        records = byID
        targetReceipts = receipts
        self.catalog = catalog
    }

    public func status(of id: String) -> LawPromotedEvidenceStatus {
        guard let entry = records[id], entry.record.type == LawRecordType.evidence.rawValue else { return .notClaimed }
        // 원본 쪽 영수증(이 기록을 원본으로 적은 영수증)은 승격본 주장이 아니다.
        let receipts = (targetReceipts[id] ?? []).filter {
            $0.world == entry.world && PromotionReceipt.decode(body: $0.record.body)?.sourceObjectId != id
        }
        guard entry.record.tags.contains(Self.promotedTag) || !receipts.isEmpty else { return .notClaimed }
        guard let catalog, let world = entry.world else { return .unproven("승격본을 확인할 원장 설정이 없음") }
        var reason = "대상 영수증 없음"
        for receipt in receipts {
            guard let problem = verify(
                receiptBody: receipt.record.body, evidenceID: id, evidence: entry.record, world: world,
                catalog: catalog)
            else { return .genuine }
            reason = problem
        }
        return .unproven(reason)
    }

    /// 대상 영수증 하나를 원본 원장에서 대조한다. 통과하면 nil, 아니면 이유.
    func verify(
        receiptBody: String, evidenceID: String, evidence: LawRecord, world: String, catalog: WorldBindingCatalog
    ) -> String? {
        guard let receipt = PromotionReceipt.decode(body: receiptBody) else { return "영수증 형식 오류" }
        guard receipt.targetObjectId == evidenceID, receipt.targetWorld == world else { return "영수증의 대상이 다름" }
        guard receipt.sourceKind == "world", let sourceName = receipt.sourceWorldName,
              let binding = catalog.world(named: sourceName), catalog.isLedgerThree(sourceName)
        else { return "영수증의 원본 원장이 설정에 없음" }
        guard catalog.isAncestor(world, of: sourceName) else { return "원본 원장이 대상의 하위 원장이 아님" }
        guard Self.canonical(binding.rootPath) == Self.canonical(receipt.sourceWorldRoot) else {
            return "영수증의 원본 원장 루트가 설정과 다름"
        }
        let scanned = LawStore(root: URL(fileURLWithPath: binding.rootPath)).scan()
        let hasSourceReceipt = scanned.contains { stored in
            stored.record.type == LawRecordType.promotionReceipt.rawValue
                && stored.record.body == receiptBody
                && stored.record.contentID() == stored.id
                && stored.record.cites.contains(LawCite(id: receipt.sourceObjectId, rel: LawRelation.receipts.rawValue))
                && stored.record.cites.contains(LawCite(id: evidenceID, rel: LawRelation.promotedAs.rawValue))
        }
        guard hasSourceReceipt else { return "원본 원장에 같은 영수증이 없음" }
        guard let source = scanned.first(where: { $0.id == receipt.sourceObjectId }),
              source.record.contentID() == source.id
        else { return "원본 증거 기록이 없거나 코어가 다름" }
        guard source.record.type == LawRecordType.evidence.rawValue,
              source.record.speaker == evidence.speaker,
              source.record.exhibits == evidence.exhibits,
              source.record.body == evidence.body
        else { return "원본 증거 기록과 화자·증거물·본문이 다름" }
        return nil
    }

    static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

/// 승격 중인 증거의 증언 확인자. 원본 원장 범위에서 다시 확인한 화자를, 요청이 원본 증거와 같을 때만 돌려준다.
/// 승격 경로(`LawPromotionService`)만 만든다 — 일반 공포 경로의 기본 확인자는 세션 대조다.
struct LawPromotionTestimony: LawTestimonyVerifying {
    let session: String?
    let runtime: String?
    let device: String?
    let exhibits: [String]
    let witnessed: LawSpeaker

    func speaker(for request: LawTestimonyRequest) throws -> LawSpeaker? {
        guard request.session == session, request.runtime == runtime, request.device == device,
              request.quotes.map(\.sha256) == exhibits else { return nil }
        return witnessed
    }

    /// 원본 증거 기록의 증언을 원본 원장 범위(`LawSessionTestimony(target: 원본)`)에서 다시 확인한다.
    /// 세션 증언이 필요 없는 증거(머리 칸 session 없음, user 화자 아님)는 nil 을 돌려준다.
    static func reverify(_ stored: LawStoredRecord, source: LawLedgerTarget) throws -> LawPromotionTestimony? {
        let record = stored.record
        let head = (try? LawHeadFields.parse(body: record.body, type: record.type)) ?? .empty
        guard head["session"] != nil || record.speaker == LawSpeaker.user.rawValue else { return nil }
        let quotes = record.exhibits.map { sha in
            LawExhibitQuote(sha256: sha, text: (try? source.store.exhibit(sha256: sha)).flatMap {
                String(data: $0, encoding: .utf8)
            })
        }
        let request = LawTestimonyRequest(
            session: head["session"], utteranceAt: head["utterance-at"], runtime: head["runtime"],
            device: head["device"], quotes: quotes)
        guard !quotes.isEmpty, let witnessed = try LawSessionTestimony(target: source).speaker(for: request) else {
            throw LawPromotionError.testimonyRefused(stored.id)
        }
        guard record.speaker == nil || record.speaker == witnessed.rawValue else {
            throw LawPromotionError.testimonyRefused(stored.id)
        }
        return LawPromotionTestimony(
            session: head["session"], runtime: head["runtime"], device: head["device"], exhibits: record.exhibits,
            witnessed: witnessed)
    }
}
