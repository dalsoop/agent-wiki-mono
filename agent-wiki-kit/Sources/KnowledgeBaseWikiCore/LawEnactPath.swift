import Foundation
import WikiLedgerKit

// 처리 유형별 허용 공포 경로 — 판정은 이 한 곳(`LawEnactService.enact` 가 공포 전에 부른다).
// 일반 공포(`enact`·`amend`·`repeal` CLI, 화면 편집)는 처리 유형(`ruling`·`appeal`·`proposal`·`redaction`·`registration`·
// `contents`·`report`·`promotion-receipt`·`finding`)을 공포하지 못하고, 그 유형을 만드는 전용 명령의 서비스만 공포한다.
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
    /// - 승격(`promote`)은 원본 기록을 유형·태그 그대로 옮기므로 유형·태그를 보지 않는다.
    /// - 폐지만 하는 초안(`repeals` 만, 개정 없음)은 대상 유형을 그대로 적으므로 어느 경로나 받는다.
    public func admit(_ draft: LawDraft) throws -> LawDraft {
        guard self != .promote else { return draft }
        if let reserved = draft.tags.first(where: { $0.hasPrefix(Self.reservedTagPrefix) }) {
            throw LawEnactError.reservedTag(reserved)
        }
        let repealOnly = draft.repeals != nil && draft.amends == nil && draft.amendsAlso.isEmpty
        if let type = LawRecordType(rawValue: draft.type), let allowed = Self.restrictedTypes[type],
           !allowed.contains(self), !repealOnly {
            throw LawEnactError.typeRequiresDedicatedCommand(type: type.rawValue, command: Self.dedicatedCommand(for: type))
        }
        var admitted = draft
        if self == .redact, draft.type == LawRecordType.redaction.rawValue {
            admitted.tags.append(Self.redactionMarkerTag)
        }
        return admitted
    }
}
