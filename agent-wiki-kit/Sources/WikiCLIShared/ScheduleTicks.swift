import Foundation
import KnowledgeBaseWikiCore

// 예약 실행 틱 목록 — 전역 CLI 의 `schedule` 이 LaunchAgent(CLI 를 부르는 순수 plist)로 등록한다.
// ledger 3 전환 뒤의 대응: 체크포인트는 기본 원장(`agent-law`)에 앱 작성자로, 검증은 `audit`, 그리고 동기화 10분·
// 적재 하루·드리밍 하루. 옛 `tick librarian|reaper|retrospective` 는 ledger 3 대응이 없어 빼고 `schedule` 이 거둔다.
// 근거: docs/operations.md "정기 작업과 동기화", docs/architecture.md "agent-law" 예약 실행, 결정 0007.

/// 예약 실행 간격 — 달력 시각(StartCalendarInterval) 또는 초 간격(StartInterval).
public enum ScheduleInterval: Equatable, Sendable {
    case calendar([String: Int])
    case every(seconds: Int)
}

/// LaunchAgent 하나 = CLI 를 부르는 순수 plist 하나(RunAtLoad 없음).
public struct ScheduleTick: Equatable, Sendable {
    public let role: String
    /// CLI 뒤에 붙는 인자.
    public let arguments: [String]
    public let interval: ScheduleInterval

    public init(role: String, arguments: [String], interval: ScheduleInterval) {
        self.role = role
        self.arguments = arguments
        self.interval = interval
    }
}

public let scheduleTicks: [ScheduleTick] = [
    ScheduleTick(
        role: "checkpoint", arguments: ["--as", "app:\(LawCourtService.appSlug)", "checkpoint"],
        interval: .calendar(["Hour": 21, "Minute": 30])),
    ScheduleTick(role: "verifier", arguments: ["audit"], interval: .calendar(["Hour": 4, "Minute": 30, "Weekday": 1])),
    ScheduleTick(role: "law-sync", arguments: ["sync"], interval: .every(seconds: 600)),
    ScheduleTick(role: "law-archive", arguments: ["archive"], interval: .calendar(["Hour": 2, "Minute": 0])),
    ScheduleTick(role: "law-dream", arguments: ["dream", "run", "--scheduled"], interval: .calendar(["Hour": 2, "Minute": 30])),
]

/// ledger 3 대응이 없어 예약에서 뺀 옛 틱. `schedule` 이 남은 plist 를 거둔다.
public let retiredScheduleRoles = ["librarian", "run-reaper", "retrospective"]
