import Foundation

/// 사이드바 3 영역 — 소유권 축이 곧 화면 구조다.
enum LedgerArea: Hashable {
    case myNotes    // 인간 판단 레이어 (가변 감각)
    case evidence   // 불변 근거 보관소 (발행만, 수정 없음)
    case activity   // 에이전트 활동 (batch 단위, 되돌리기)
    case graph      // 관계도 (옵시디언식 force 그래프)
    case events     // 사건 로그 — "무엇이 언제 일어났나"(events/*.ndjson, 사실층)
    case changes    // 최근 변경 — 지식 문서 신규·개정·철회 피드(나무위키 RecentChanges)
    case discuss    // 토론 — 이의·질문·수정요청 스레드(나무위키 토론), 미답변 우선
    case learning   // 학습 — 회고 에이전트의 경험칙·시간별 지표(카르파시식 경험학습)
    case triage     // 수집함 — 유입 트리아지 (킵/버림)
    case review     // 심사대 — 정제본 검증 현황·확립 게이트
    case agents     // 에이전트 명단·발행 이력
    case wiki       // 위키 층 — 사서(wiki-maintainer)가 유지하는 개념 페이지·색인
    case trash      // 휴지통 — 철회(폐기)된 것들. 역사는 남고, 복원 발행 가능
    case structure  // 구조 — 저장 3층과 층 사이 배선 완성도(실측)
    case settings   // 설정 — 일반·스케줄러·에이전트 연동·백업

    /// 조종 키(`app area <key>`) → 영역. exhaustive switch 라 새 case 를 추가하면
    /// 여기서 컴파일 에러가 나 CLI 키(LedgerAreaKey.all)와 조용히 갈라지지 않는다.
    init?(controlKey: String) {
        switch controlKey {
        case "myNotes": self = .myNotes
        case "evidence": self = .evidence
        case "activity": self = .activity
        case "graph": self = .graph
        case "events": self = .events
        case "changes": self = .changes
        case "discuss": self = .discuss
        case "learning": self = .learning
        case "triage": self = .triage
        case "review": self = .review
        case "agents": self = .agents
        case "wiki": self = .wiki
        case "trash": self = .trash
        case "structure": self = .structure
        case "settings": self = .settings
        default: return nil
        }
    }

    /// 조종 키 — 위 init 의 역방향. 새 case 추가 시 컴파일러가 여기도 채우게 강제한다.
    var controlKey: String {
        switch self {
        case .myNotes: return "myNotes"
        case .evidence: return "evidence"
        case .activity: return "activity"
        case .graph: return "graph"
        case .events: return "events"
        case .changes: return "changes"
        case .discuss: return "discuss"
        case .learning: return "learning"
        case .triage: return "triage"
        case .review: return "review"
        case .agents: return "agents"
        case .wiki: return "wiki"
        case .trash: return "trash"
        case .structure: return "structure"
        case .settings: return "settings"
        }
    }
}
