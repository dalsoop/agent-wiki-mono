import Foundation
import WikiLedgerKit

// 심급 화면 표시 모델 — 항소심 대기, 대법원 대기(공지 시각·이의 기간 종료 시각), 닫힌 건(결정 결과·결정한 모델 또는 사용자 증언).
// 닫힌 건은 엔진이 사건을 닫을 때 쓰는 유효성 검사(`LawCourtDocket.isValidAppellate`·`isValidSupreme`)를 거친 목록
// (`LawCourtDocket.closed`)이다 — 화면이 `hears` 만 보고 고르지 않는다.
// 근거: docs/business-rules.md "심급제".

public struct LawCourtScreen: Sendable {
    public let appellate: [LawCourtCase]
    /// 대법원 대기(공지 순). 공지 시각 `noticedAt`, 이의 기간 종료(결정 가능) 시각 `decidableAt`.
    public let supreme: [LawCourtCase]
    /// 닫힌 건(결정 시각 새것 먼저).
    public let closed: [LawClosedCase]
    public let objectionPeriod: TimeInterval

    public init(docket: LawCourtDocket) {
        appellate = docket.appellatePending
        supreme = docket.supremePending.sorted { ($0.noticedAt, $0.id) < ($1.noticedAt, $1.id) }
        closed = docket.closed.sorted { ($0.decidedAt, $0.id) > ($1.decidedAt, $1.id) }
        objectionPeriod = docket.objectionPeriod
    }

    public var isEmpty: Bool { appellate.isEmpty && supreme.isEmpty && closed.isEmpty }

    /// 원장 하나를 읽어 만든다(설정의 이의 기간). 화면은 배경에서 부른다.
    public static func load(target: LawLedgerTarget) -> LawCourtScreen {
        LawCourtScreen(docket: LawCourtDocket.of(target))
    }
}
