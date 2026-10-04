import Foundation
import WikiLedgerKit

// ledger 3 승격 — `promote <id> --to <원장>`. 영수증 규칙은 옛 승격과 같다:
// 대상 원장에 승격본과 대상 영수증, 원본 원장에 원본 영수증(`receipts` → 원본, `promoted-as` → 승격본).
// ledger 3 관계 집합에 `promotes` 가 없고 상위 원장은 하위를 인용할 수 없으므로, 대상 쪽 기록은 원본을
// 인용하지 않고 영수증 본문(JSON)에 원본 id·원장을 적는다.
// 승격 허용 판정은 `WorldPromotionGate`, 쓰기 거부는 `WorldWriteGate`(공포 경로 안)에만 둔다.
// 증거(`evidence`) 승격은 원본 원장 범위에서 증언을 다시 확인하고 통과해야 하며, 증거물도 대상 원장에 복사한다.
// 승격본의 화자는 그 뒤 승격 영수증이 증언 확인을 대신한다(`LawPromotionWitness`, LawPromotedEvidence.swift).
// 근거: docs/contracts.md "승격"·"agent-law 명령", docs/business-rules.md "관계", 결정 0007.

public struct LawPromotionResult: Codable, Sendable, Equatable {
    public let promotedObjectId: String
    public let targetReceiptObjectId: String?
    public let sourceReceiptObjectId: String
    public let targetWorld: String
    public let deduplicated: Bool
}

public enum LawPromotionError: Error, CustomStringConvertible {
    case gate(String)
    case sourceMissing(String)
    case sourceIsReceipt
    case sourceTampered(String)
    case testimonyRefused(String)
    case exhibitMissing(String)
    case service(LawEnactServiceError)

    public var description: String {
        switch self {
        case .gate(let message): return message
        case .sourceMissing(let id): return "원본 기록을 찾을 수 없음: \(id)"
        case .sourceIsReceipt: return "승격 영수증은 승격할 수 없음"
        case .sourceTampered(let id): return "원본이 저장된 바이트와 다름(코어 재해시 불일치): \(id)"
        case .testimonyRefused(let id): return "원본 원장 범위에서 증언을 다시 확인하지 못해 승격 거부(증언 불일치): \(id)"
        case .exhibitMissing(let sha): return "증거 기록의 증거물을 원본 원장에서 찾을 수 없어 승격 거부: \(sha)"
        case .service(let error): return error.description
        }
    }
}

public enum LawPromotionService {
    public static func promote(
        sourceID: String, source: LawLedgerTarget, targetWorld rawTarget: String,
        actor: LawActor, now: Date = Date()
    ) throws -> LawPromotionResult {
        let targetName = WorldPromotionGate.canonicalTargetName(rawTarget)
        if let denial = WorldPromotionGate.denial(
            currentWorld: source.worldName, targetWorld: targetName, catalog: source.catalog) {
            throw LawPromotionError.gate(denial)
        }
        guard let targetBinding = source.catalog.world(named: targetName) else {
            throw LawPromotionError.gate("unknown target world: \(targetName)")
        }
        let target = LawLedgerTarget(
            worldName: targetName, root: URL(fileURLWithPath: targetBinding.rootPath), catalog: source.catalog,
            registeredDevices: source.registeredDevices, currentDevice: source.currentDevice, file: source.file,
            summonSources: source.summonOverride)
        guard let stored = source.store.scan().first(where: { $0.id == sourceID }) else {
            throw LawPromotionError.sourceMissing(sourceID)
        }
        guard stored.record.type != LawRecordType.promotionReceipt.rawValue else { throw LawPromotionError.sourceIsReceipt }
        guard stored.record.contentID() == stored.id else { throw LawPromotionError.sourceTampered(sourceID) }

        let sourceRoot = source.root.standardizedFileURL.path
        if let existing = existingReceipt(in: target.store, sourceID: sourceID, sourceRoot: sourceRoot)
            ?? existingReceipt(in: source.store, sourceID: sourceID, sourceRoot: sourceRoot) {
            let sourceReceipt = try ensureSourceReceipt(existing.receipt, source: source, actor: actor, now: now)
            let targetReceipt = receiptRecord(in: target.store, sourceID: sourceID, sourceRoot: sourceRoot)
            return LawPromotionResult(
                promotedObjectId: existing.receipt.targetObjectId, targetReceiptObjectId: targetReceipt,
                sourceReceiptObjectId: sourceReceipt, targetWorld: targetName, deduplicated: true)
        }

        let record = stored.record
        let isEvidence = record.type == LawRecordType.evidence.rawValue
        // 증거 기록: 쓰기 전에 원본 원장 범위에서 증언을 다시 확인한다(실패하면 아무것도 쓰지 않고 거부).
        let testimony = isEvidence ? try LawPromotionTestimony.reverify(stored, source: source) : nil
        let targetIndex = LawEnactService.scope(of: target)
        for sha in record.exhibits {
            if isEvidence {
                _ = try target.store.putExhibit(exhibitData(sha, source: source))
            } else if let data = try? source.store.exhibit(sha256: sha) {
                _ = try? target.store.putExhibit(data)
            }
        }
        let keptCites = record.cites.filter { targetIndex.object(id: $0.id) != nil }
        // 승격된 증거 기록은 화자를 그대로 가진다(위에서 다시 확인한 화자). 그 밖의 user 화자는 증언 인용이 없으면 비운다.
        let speaker = isEvidence || record.speaker != LawSpeaker.user.rawValue || actor.kind == .human
            ? record.speaker : nil
        let promoted = try serviceCall {
            try LawEnactService.enact(LawDraft(
                actor: actor, speaker: speaker, title: record.title,
                type: record.type ?? LawRecordType.record.rawValue,
                origin: record.origin == LawOrigin.dream.rawValue ? record.origin : nil,
                tags: Array(Set(record.tags + [LawPromotionWitness.promotedTag])).sorted(), cites: keptCites,
                exhibits: record.exhibits, body: record.body), target: target, index: targetIndex,
                testimony: testimony, now: now)
        }
        let receipt = PromotionReceipt(PromotionReceipt.Draft(
            sourceKind: "world", sourceWorldName: source.worldName, sourceObjectId: sourceID,
            sourceWorldRoot: sourceRoot, targetWorld: targetName,
            targetWorldRoot: target.root.standardizedFileURL.path, targetObjectId: promoted.id,
            promotedAt: now, promotedBy: actor.author))
        let sourceReceipt = try ensureSourceReceipt(receipt, source: source, actor: actor, now: now)
        let body = try encodedReceipt(receipt)
        let targetReceipt = try serviceCall {
            try LawEnactService.enact(LawDraft(
                actor: actor, title: "프로모션 영수증: \(record.title ?? String(sourceID.prefix(12)))",
                type: LawRecordType.promotionReceipt.rawValue,
                cites: [LawCite(id: promoted.id, rel: LawRelation.receipts.rawValue)],
                body: body), target: target, now: now)
        }
        return LawPromotionResult(
            promotedObjectId: promoted.id, targetReceiptObjectId: targetReceipt.id,
            sourceReceiptObjectId: sourceReceipt, targetWorld: targetName, deduplicated: false)
    }

    /// 증거물 바이트 — 원본 원장의 로컬 파일, 없으면 원본 원장 키의 R2 증거물. 내용 sha256 이 이름과 같아야 한다.
    /// 대상 원장 키의 R2 사본은 다음 `sync` 가 올린다.
    static func exhibitData(_ sha: String, source: LawLedgerTarget) throws -> Data {
        if let data = try? source.store.exhibit(sha256: sha), LawHash.sha256Hex(data) == sha { return data }
        if let key = source.catalog.world(named: source.worldName)?.key,
           let store = try? source.summonSources.objectStore(),
           let data = try? store.get(key: LawArchiveKeys.exhibit(ledgerKey: key, sha256: sha)),
           LawHash.sha256Hex(data) == sha {
            return data
        }
        throw LawPromotionError.exhibitMissing(sha)
    }

    static func ensureSourceReceipt(
        _ receipt: PromotionReceipt, source: LawLedgerTarget, actor: LawActor, now: Date
    ) throws -> String {
        let body = try encodedReceipt(receipt)
        if let existing = source.store.scan().first(where: {
            $0.record.type == LawRecordType.promotionReceipt.rawValue && $0.record.body == body
        }) { return existing.id }
        return try serviceCall {
            try LawEnactService.enact(LawDraft(
                actor: actor,
                title: "프로모션 링크: \(String(receipt.sourceObjectId.prefix(12))) → \(receipt.targetWorld)",
                type: LawRecordType.promotionReceipt.rawValue,
                cites: [
                    LawCite(id: receipt.sourceObjectId, rel: LawRelation.receipts.rawValue),
                    LawCite(id: receipt.targetObjectId, rel: LawRelation.promotedAs.rawValue),
                ],
                body: body), target: source, now: now)
        }.id
    }

    static func encodedReceipt(_ receipt: PromotionReceipt) throws -> String {
        do { return try receipt.json() } catch {
            throw LawPromotionError.gate("영수증 인코딩 실패: \(error)")
        }
    }

    static func existingReceipt(
        in store: LawStore, sourceID: String, sourceRoot: String
    ) -> (id: String, receipt: PromotionReceipt)? {
        for stored in store.scan() where stored.record.type == LawRecordType.promotionReceipt.rawValue {
            guard let receipt = PromotionReceipt.decode(body: stored.record.body),
                  receipt.sourceObjectId == sourceID, receipt.sourceWorldRoot == sourceRoot else { continue }
            return (stored.id, receipt)
        }
        return nil
    }

    static func receiptRecord(in store: LawStore, sourceID: String, sourceRoot: String) -> String? {
        existingReceipt(in: store, sourceID: sourceID, sourceRoot: sourceRoot)?.id
    }

    static func serviceCall<T>(_ body: () throws -> T) throws -> T {
        do { return try body() } catch let error as LawEnactServiceError {
            throw LawPromotionError.service(error)
        }
    }
}
