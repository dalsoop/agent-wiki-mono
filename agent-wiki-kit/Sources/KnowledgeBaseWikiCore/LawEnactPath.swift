import Foundation
import WikiLedgerKit

// 처리 유형별 허용 공포 경로 — 판정은 이 한 곳(`LawEnactService.enact` 가 공포 전에 부른다).
// 일반 공포(`enact`·`amend`·`repeal` CLI, 화면 편집)는 처리 유형(`ruling`·`appeal`·`proposal`·`redaction`·`registration`·
// `contents`·`report`·`promotion-receipt`·`finding`)을 공포하지 못하고, 그 유형을 만드는 전용 명령의 서비스만 공포한다.
// 개정·폐지는 대상 기록의 실제 유형으로 판정한다(`targetPaths`): 대법원 결정·가림·승격 영수증은 어느 경로로도 못 하고, 처리 기록은 그 전용 경로만.
// 원상회복(`LawStore.restore`)이 만드는 기록도 모두 여기를 지난다(기록별 경로는 `LawRestorePaths` — 드리밍 묶음은 반드시 되돌릴 수 있게).
// 확정 판결 등록의 개정·폐지는 대법원 결정 인용, 확정은 사용자 발화 증언이 필요하다(`checkRegistration`).
// 가림 기록은 `redact` 경로가 예약 태그(`path:redact`)를 붙이고, 가림 동기화·감사는 그 표지가 있는 기록만 믿는다.
// 근거: docs/business-rules.md "유형"·"공포·개정·폐지·원상회복", docs/security.md "작성자·화자 신뢰"·"R2 와 세션", 결정 0007.

/// 공포를 부른 경로(서비스). 기록 코어에는 들어가지 않는다(가림의 예약 태그만 남는다).
public enum LawEnactPath: String, Sendable, CaseIterable {
    /// `enact`·`amend`·`repeal` CLI, 화면 편집(`LedgerHumanEdit`), 그 밖의 일반 공포.
    case general
    /// `court` — 이의·개정안·항소심·대법원 결정과 그 조치.
    case court
    /// `redact` — 가림 기록.
    case redact
    /// `judgment` — 판결 등록과 그 개정.
    case judgment
    /// `dream` — 드리밍 묶음·보고·`dream resume`.
    case dream
    /// `contents` — 목차(드리밍의 목차 새 판도 이 경로).
    case contents
    /// `promote` — 승격본(원본 유형 그대로)과 승격 영수증.
    case promote
    /// `finding` — 사실인정.
    case finding

    /// 가림 경로가 붙이는 예약 태그. 일반 경로는 `path:` 로 시작하는 태그를 받지 않는다.
    public static let redactionMarkerTag = "path:redact"
    static let reservedTagPrefix = "path:"

    /// 처리 유형 → 공포할 수 있는 경로. 표에 없는 유형은 어느 경로나 공포한다.
    public static let restrictedTypes: [LawRecordType: Set<LawEnactPath>] = [
        .ruling: [.court], .appeal: [.court], .proposal: [.court],
        .redaction: [.redact], .registration: [.judgment], .contents: [.contents],
        .report: [.dream], .promotionReceipt: [.promote], .finding: [.finding, .dream],
    ]

    /// 거부 안내에 적는 전용 명령.
    public static func dedicatedCommand(for type: LawRecordType) -> String {
        switch type {
        case .ruling, .appeal, .proposal: return "court"
        case .redaction: return "redact"
        case .registration: return "judgment"
        case .contents: return "contents"
        case .report: return "dream"
        case .promotionReceipt: return "promote"
        case .finding: return "finding"
        default: return "enact"
        }
    }

    /// 이 경로가 이 초안을 공포할 수 있나. 통과하면 경로 표지를 붙인 초안을 돌려준다.
    /// - 초안 자신의 유형: 처리 유형은 그 전용 경로만(`restrictedTypes`). 폐지만 하는 초안이 대상 유형을 그대로 적었으면
    ///   대상 판정만 본다(예: 드리밍의 목차·보고 폐지). 다른 유형을 적으면 그 유형으로 판정한다.
    /// - 개정·폐지 대상(`amends`·`amends-also`·`repeals`)의 실제 유형: `targetPaths` 가 허용한 경로만. 초안이 적은 유형이
    ///   아니라 `target` 이 찾아 준 대상 기록을 본다(유형을 바꿔 적어 우회하지 못하게).
    ///   찾지 못한 대상(범위 밖)은 공포 검증이 거부하고, 전신(ledger 2) 객체는 유형 판정이 없다.
    /// - 승격(`promote`)은 원본 기록을 유형·태그 그대로 새로 공포하므로 초안의 유형·태그를 보지 않는다(대상 판정은 본다).
    /// - Parameter target: 대상 id → 기록(같은 원장과 허용 범위). 공포 서비스·원상회복이 넣는다.
    public func admit(_ draft: LawDraft, target: (String) -> LawRecord?) throws -> LawDraft {
        // 폐지만 하는 초안이 대상 유형을 그대로 적었으면 유형 판정은 대상 판정(아래)이 대신한다.
        // 대법원 결정의 조치(`court`)가 확정 판결 등록을 같은 유형으로 개정하는 것도 그렇다(대법원 인용은 `checkRegistration`).
        let copiesTargetType = (LawEnactValidator.repealOnly(draft)
            && draft.repeals.flatMap(target).map { ($0.type ?? LawRecordType.record.rawValue) == draft.type } == true)
            || (self == .court && draft.type == LawRecordType.registration.rawValue && draft.amends != nil
                && ([draft.amends].compactMap { $0 } + draft.amendsAlso).allSatisfy {
                    target($0).map(Self.isConfirmedRegistration) == true
                })
        if self != .promote {
            if let reserved = draft.tags.first(where: { $0.hasPrefix(Self.reservedTagPrefix) }) {
                throw LawEnactError.reservedTag(reserved)
            }
            if !copiesTargetType, let type = LawRecordType(rawValue: draft.type),
               let allowed = Self.restrictedTypes[type], !allowed.contains(self) {
                throw LawEnactError.typeRequiresDedicatedCommand(type: type.rawValue, command: Self.dedicatedCommand(for: type))
            }
        }
        let changed = [draft.amends, draft.repeals].compactMap { $0 } + draft.amendsAlso
        for id in changed {
            guard let record = target(id), let rule = Self.targetPaths(for: record) else { continue }
            let type = record.type ?? LawRecordType.record.rawValue
            if rule.isEmpty { throw LawEnactError.targetIrreversible(target: id, type: Self.targetLabel(record)) }
            if !rule.contains(self) {
                throw LawEnactError.targetRequiresDedicatedCommand(
                    target: id, type: type, command: rule.map(\.rawValue).sorted().joined(separator: "·"))
            }
        }
        try Self.checkRegistration(draft, changed: changed, target: target)
        var admitted = draft
        if self == .redact, draft.type == LawRecordType.redaction.rawValue {
            admitted.tags.append(Self.redactionMarkerTag)
        }
        return admitted
    }

    /// 개정·폐지 대상 기록 → 그것을 개정·폐지할 수 있는 경로. nil 은 어느 경로나(지식 기록 등), 빈 집합은 어느 경로도 못 함.
    /// - `ruling` 의 `level: supreme`: 없음(대법원 결정은 최종). 항소심 `ruling`·`appeal`·`proposal`: `court`.
    /// - `registration`: 잠정이면 `judgment`, 확정이면 `judgment`·`court`(어느 쪽이든 대법원 결정 인용이 필요 — `checkRegistration`).
    /// - `redaction`: 없음(지운 증거물은 돌아오지 않으므로 가림은 되돌릴 수 없다).
    /// - `promotion-receipt`: 없음(승격본의 무결성 기록 — 고치거나 지우면 승격 확인이 깨진다).
    /// - `contents`·`report`: `dream`·`contents`. `finding`: `finding`·`dream`.
    public static func targetPaths(for record: LawRecord) -> Set<LawEnactPath>? {
        switch LawRecordType(rawValue: record.type ?? LawRecordType.record.rawValue) {
        case .ruling?: return isSupreme(record) ? [] : [.court]
        case .appeal?, .proposal?: return [.court]
        case .registration?: return isConfirmedRegistration(record) ? [.judgment, .court] : [.judgment]
        case .redaction?, .promotionReceipt?: return []
        case .contents?, .report?: return [.dream, .contents]
        case .finding?: return [.finding, .dream]
        default: return nil
        }
    }

    static func isSupreme(_ record: LawRecord) -> Bool {
        let head = try? LawHeadFields.parse(body: record.body, type: record.type)
        return head?["level"] == LawRulingLevel.supreme.rawValue
    }

    static func targetLabel(_ record: LawRecord) -> String {
        if record.type == LawRecordType.ruling.rawValue, isSupreme(record) { return "ruling(level: supreme)" }
        return record.type ?? LawRecordType.record.rawValue
    }

    // MARK: - 판결 등록의 확정

    /// `status: confirmed` 인 판결 등록.
    public static func isConfirmedRegistration(_ record: LawRecord) -> Bool {
        guard record.type == LawRecordType.registration.rawValue else { return false }
        return (try? LawHeadFields.parse(body: record.body, type: record.type))?["status"]
            == LawRegistrationStatus.confirmed.rawValue
    }

    /// 판결 등록의 확정 규칙(사용자 결정 2026-10-04 "확정 변경은 대법원으로").
    /// - 확정(`status: confirmed`) 판결 등록의 개정·폐지(잠정으로 되돌림 포함)는 대법원 결정(`ruling` `level: supreme`)을
    ///   `per-ruling` 으로 인용해야 한다. 경로(`judgment`·`court`)와 무관하다.
    /// - 확정판을 새로 만드는 등록·개정(잠정 → 확정, 확정으로 처음 등록)은 사용자 발화 증언(`speaker: user` 증거를
    ///   `testifies`)이 있어야 한다. 대법원 결정에 따른 개정이면 그 결정이 증언을 대신한다.
    /// - 잠정 판결의 경로·제목 수정은 그대로 된다.
    static func checkRegistration(_ draft: LawDraft, changed: [String], target: (String) -> LawRecord?) throws {
        let supreme = citesSupremeRuling(draft, target: target)
        for id in changed {
            guard let record = target(id), isConfirmedRegistration(record), !supreme else { continue }
            throw LawEnactError.confirmedJudgmentRequiresSupreme(target: id)
        }
        guard draft.type == LawRecordType.registration.rawValue, !LawEnactValidator.repealOnly(draft),
              (try? LawHeadFields.parse(body: draft.body, type: draft.type))?["status"]
                == LawRegistrationStatus.confirmed.rawValue
        else { return }
        guard supreme || citesUserTestimony(draft, target: target) else {
            throw LawEnactError.judgmentConfirmRequiresTestimony
        }
    }

    /// 대법원 결정을 `per-ruling` 으로 인용했나.
    static func citesSupremeRuling(_ draft: LawDraft, target: (String) -> LawRecord?) -> Bool {
        draft.cites.contains { cite in
            guard cite.rel == LawRelation.perRuling.rawValue, let ruling = target(cite.id) else { return false }
            return ruling.type == LawRecordType.ruling.rawValue && isSupreme(ruling)
        }
    }

    /// `speaker: user` 증거(드리밍 정리본 아님)를 `testifies` 로 인용했나.
    static func citesUserTestimony(_ draft: LawDraft, target: (String) -> LawRecord?) -> Bool {
        draft.cites.contains { cite in
            guard cite.rel == LawRelation.testifies.rawValue, let evidence = target(cite.id) else { return false }
            return evidence.type == LawRecordType.evidence.rawValue && evidence.speaker == LawSpeaker.user.rawValue
                && evidence.origin != LawOrigin.dream.rawValue
        }
    }
}

// MARK: - 원상회복의 경로

/// 원상회복이 묶음의 기록 하나를 되돌릴 때 쓰는 경로. 판정은 여기 한 곳이다(`LawStore.restore` 가 부른다).
/// - 일반 묶음: 원상회복을 부른 경로 그대로(지금 규칙).
/// - 드리밍 묶음(드리밍 보고가 적은 묶음 id, `LawDreamMarks.dreamBatches`) 안에서 드리밍(`app:agent-wiki`)이 만든 기록
///   (사용자 결정 "자동 적용 + 묶음 되돌리기" — 드리밍 묶음은 반드시 되돌릴 수 있어야 한다):
///   - 사실인정·목차·보고: `dream` 경로.
///   - 드리밍이 낸 이의·개정안: 아직 심리되지 않았으면(그 건을 `hears` 로 인용한 결정이 없으면) `court` 경로.
///     이미 결정이 난 건은 거부한다(결정의 근거를 지우지 않는다 — 다툼은 상고로).
///   - 그 밖(지식 기록·이관 기록)은 부른 경로 그대로.
///   드리밍 묶음 안이라도 드리밍이 만들지 않은 기록은 부른 경로 그대로다.
/// 근거: docs/business-rules.md "드리밍"(안전장치)·"공포·개정·폐지·원상회복".
public struct LawRestorePaths: Sendable {
    let dreamBatches: Set<String>
    let heardCases: Set<String>

    public init(records: [LawStoredRecord]) {
        dreamBatches = LawDreamMarks(records: records).dreamBatches
        heardCases = Set(records.filter { $0.record.type == LawRecordType.ruling.rawValue }
            .flatMap { $0.record.cites.filter { $0.rel == LawRelation.hears.rawValue }.map(\.id) })
    }

    public func isDreamBatch(_ batch: String) -> Bool { dreamBatches.contains(batch) }

    /// 묶음 `batch` 의 기록 `target` 을 되돌릴 경로. 이미 결정이 난 드리밍 이의·개정안이면 거부한다.
    public func path(for target: LawStoredRecord, batch: String, caller: LawEnactPath) throws -> LawEnactPath {
        let record = target.record
        guard isDreamBatch(batch), record.batch == batch, record.author == LawDreamRecordFormat.appAuthor,
              record.authorKind == LawAuthorKind.app.rawValue
        else { return caller }
        switch LawRecordType(rawValue: record.type ?? LawRecordType.record.rawValue) {
        case .finding?, .contents?, .report?:
            return .dream
        case .appeal?, .proposal?:
            if heardCases.contains(target.id) {
                throw LawEnactError.restoreDecidedCase(target: target.id, type: record.type ?? "")
            }
            return .court
        default:
            return caller
        }
    }
}
