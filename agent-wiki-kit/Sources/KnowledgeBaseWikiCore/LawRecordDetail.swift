import Foundation
import WikiLedgerKit

// 기록 상세(출처 패널) 표시 모델 — 저장하지 않는 보기.
// 작성자·모델 기록·화자·공포일, 증언(`testifies` 로 인용한 증거 기록의 인용 구절·세션·발화 시각, 증거물 부재 표시),
// 현행 사실인정, 4종류, 연혁(병합 갈래 포함), 이의·개정안과 그 결정, 인용 관계(인용한 것·인용된 것).
// 근거: docs/business-rules.md "작성자와 모델 기록"·"화자"·"본문 머리 칸"·"관계"·"사실인정과 4종류"·"심급제".

/// 작성자·모델 기록(코어 칸 그대로).
public struct LawProvenance: Sendable, Equatable {
    public let author: String
    public let authorKind: String?
    public let device: String?
    public let runtime: String?
    public let runtimeVersion: String?
    public let model: String?
    public let effort: String?
    public let app: String?
    public let appVersion: String?
    public let speaker: String?
    public let promulgated: Date

    public init(_ record: LawRecord) {
        author = record.author
        authorKind = record.authorKind
        device = record.device
        runtime = record.runtime
        runtimeVersion = record.runtimeVersion
        model = record.model
        effort = record.effort
        app = record.app
        appVersion = record.appVersion
        speaker = record.speaker
        promulgated = record.promulgated
    }
}

/// 증언 하나 — 이 기록이 `testifies` 로 인용한 증거 기록.
public struct LawTestimonyView: Sendable, Equatable {
    public let evidenceID: String
    /// 증거 기록이 있는 원장(범위 밖·없으면 nil).
    public let world: String?
    public let found: Bool
    /// 인용 구절(증거 본문의 머리 칸 뒤).
    public let quote: String?
    public let session: String?
    public let utteranceAt: String?
    public let runtime: String?
    public let device: String?
    public let speaker: String?
    public let exhibits: [String]
    /// 이 기기에 파일이 없는 증거물 — "증거물 없음(동기화 전)".
    public let missingExhibits: [String]

    public var exhibitMissing: Bool { !missingExhibits.isEmpty }
}

/// 현행 사실인정.
public struct LawFindingView: Sendable, Equatable {
    public let id: String
    public let subject: String?
    public let certainty: String?
    public let domain: String?
    public let effectiveFrom: String?
    public let effectiveUntil: String?
    public let reason: String?
    /// 판단한 작성자·모델.
    public let provenance: LawProvenance

    init(_ stored: LawStoredRecord) {
        let head = (try? LawHeadFields.parse(body: stored.record.body, type: stored.record.type)) ?? .empty
        id = stored.id
        subject = head["subject"]
        certainty = head["certainty"]
        domain = head["domain"]
        effectiveFrom = head["effective-from"]
        effectiveUntil = head["effective-until"]
        reason = head["reason"]
        provenance = LawProvenance(stored.record)
    }
}

/// 연혁 한 판 — 주 사슬(`amends`)의 판과 그 판이 병합한 갈래(`amends-also` 대상).
public struct LawHistoryEntry: Sendable, Equatable {
    public let record: LawStoredRecord
    public let isInForce: Bool
    public let mergedBranches: [LawStoredRecord]
}

/// 이 기록을 다툰 건(이의·개정안)과 그 결정.
public struct LawDisputeView: Sendable, Equatable {
    public let caseRecord: LawStoredRecord
    public let kind: LawCourtCaseKind
    /// 이 건을 `hears` 로 인용한 결정 전부(공포 순, 규칙 위반 결정 포함 — 사건을 닫았는지는 `closed`).
    public let rulings: [LawStoredRecord]
    /// 열린 건이면 대기 중인 심급.
    public let openLevel: LawRulingLevel?
    /// 닫힌 건이면 닫은 결정(엔진 유효성 검사를 통과한 결정).
    public let closed: LawClosedCase?
}

/// 인용 관계 한 줄.
public struct LawCitationLink: Sendable, Equatable {
    public let id: String
    public let rel: String
    public let title: String?
    /// 그 기록이 있는 원장(찾지 못했으면 nil).
    public let world: String?
    public let isPredecessor: Bool
}

public struct LawRecordDetail: Sendable {
    public let record: LawStoredRecord
    public let world: String
    public let isInForce: Bool
    public let provenance: LawProvenance
    public let testimonies: [LawTestimonyView]
    public let finding: LawFindingView?
    /// 4종류(`record` 유형에만, 그 밖은 nil).
    public let memoryKind: LawMemoryKind?
    public let history: [LawHistoryEntry]
    public let disputes: [LawDisputeView]
    public let cites: [LawCitationLink]
    public let citedBy: [LawCitationLink]

    /// 증거물 부재 표시.
    public static let missingExhibitLabel = "증거물 없음(동기화 전)"

    /// 만들기(파일을 읽지 않는다). `lookup` 은 같은 원장 밖 기록(상위·전신)을, `exhibitExists` 는 (원장, sha256) 의 파일 유무를 본다.
    public static func make(
        id: String, world: String, records: [LawStoredRecord], docket: LawCourtDocket,
        lookup: (String) -> LawScopeObject? = { _ in nil },
        exhibitExists: (_ world: String, _ sha256: String) -> Bool
    ) -> LawRecordDetail? {
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard let stored = byID[id] else { return nil }
        let view = LawLedgerView(records: records)
        let record = stored.record

        func locate(_ ref: String) -> (world: String, record: LawRecord?, title: String?, predecessor: Bool)? {
            if let local = byID[ref] { return (world, local.record, local.record.title, false) }
            guard let item = lookup(ref) else { return nil }
            return (item.world, item.law, item.object.title, item.isPredecessor)
        }

        let testimonies = record.cites.filter { $0.rel == LawRelation.testifies.rawValue }.map { cite in
            let found = locate(cite.id)
            let evidence = found?.record
            let head = evidence.flatMap { try? LawHeadFields.parse(body: $0.body, type: $0.type) } ?? .empty
            let exhibits = evidence?.exhibits ?? []
            return LawTestimonyView(
                evidenceID: cite.id, world: found?.world, found: evidence != nil,
                quote: evidence.map { quote(of: $0.body) }, session: head["session"], utteranceAt: head["utterance-at"],
                runtime: head["runtime"], device: head["device"], speaker: evidence?.speaker, exhibits: exhibits,
                missingExhibits: found.map { located in exhibits.filter { !exhibitExists(located.world, $0) } } ?? [])
        }

        let history = view.history(of: id).map { entry in
            LawHistoryEntry(
                record: entry, isInForce: view.isInForce(entry.id),
                mergedBranches: entry.record.amendsAlso.compactMap { byID[$0] })
        }

        let disputes: [LawDisputeView] = records.compactMap { candidate in
            guard let kind = LawCourtCaseKind(recordType: candidate.record.type),
                  candidate.record.cites.contains(where: { $0.id == id && $0.rel == kind.relation.rawValue })
            else { return nil }
            let rulings = records.filter { ruling in
                ruling.record.type == LawRecordType.ruling.rawValue
                    && ruling.record.cites.contains { $0.id == candidate.id && $0.rel == LawRelation.hears.rawValue }
            }
            return LawDisputeView(
                caseRecord: candidate, kind: kind, rulings: rulings, openLevel: docket.openCase(candidate.id)?.level,
                closed: docket.closed.first { $0.id == candidate.id })
        }

        let cites = record.cites.map { cite in
            let found = locate(cite.id)
            return LawCitationLink(
                id: cite.id, rel: cite.rel, title: found?.title, world: found?.world, isPredecessor: found?.predecessor ?? false)
        }
        let citedBy = records.flatMap { other in
            other.record.cites.filter { $0.id == id }.map { cite in
                LawCitationLink(id: other.id, rel: cite.rel, title: other.record.title, world: world, isPredecessor: false)
            }
        }

        return LawRecordDetail(
            record: stored, world: world, isInForce: view.isInForce(id), provenance: LawProvenance(record),
            testimonies: testimonies, finding: view.currentFinding(for: id).map(LawFindingView.init),
            memoryKind: view.memoryKind(of: id), history: history, disputes: disputes, cites: cites, citedBy: citedBy)
    }

    /// 원장 하나에서 읽어 만든다. `id` 는 64자 id 또는 이 원장 안에서 하나로 정해지는 앞자리(4자 이상).
    /// 이 원장에 없으면 nil(상위·전신 기록은 그 원장을 열어 본다).
    public static func load(id: String, target: LawLedgerTarget) -> LawRecordDetail? {
        let records = target.store.scan()
        guard let resolved = records.contains(where: { $0.id == id }) ? id : LawContentsScreen.resolve(prefix: id, in: records)
        else { return nil }
        let index = LawScopeIndex(current: target.worldName, catalog: target.catalog)
        let court = target.file?.court ?? LawCourtSettings()
        return make(
            id: resolved, world: target.worldName, records: records,
            docket: LawCourtDocket(records: records, objectionPeriod: court.objectionPeriod),
            lookup: { index.object(id: $0) },
            exhibitExists: { world, sha in
                guard let root = target.catalog.world(named: world)?.rootPath else { return false }
                return FileManager.default.fileExists(
                    atPath: LawStore(root: URL(fileURLWithPath: root)).exhibitURL(sha256: sha).path)
            })
    }

    /// 증거 본문의 인용 구절 — 머리 칸(첫 빈 줄 전) 뒤. 빈 줄이 없으면 본문 전체.
    static func quote(of body: String) -> String {
        guard let range = body.range(of: "\n\n") else { return body.trimmingCharacters(in: .newlines) }
        return String(body[range.upperBound...]).trimmingCharacters(in: .newlines)
    }
}
