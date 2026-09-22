import Foundation
import LocalizationKit

/// 자리 운영 보드용 파생 뷰. 원장(`Seat`) + 점검 + 디스크 관측을 한 카드로 묶는다.
///
/// 활약·니즈·피드백은 **발명하지 않는다**. 있는 신호만 라벨을 붙여 보여 준다.
/// - 니즈: health 이슈 · 경로 공유 · vault 막힘 · 작업 경로 없음 · NEEDS.md/SEAT.md
/// - 피드백: `note` + 자동 점검 실패 문장
/// - 활약: workdir mtime · git HEAD mtime · SEAT.md · 7일 파일 터치 · 고용 경과일
///   (세션 원장·Deck·forge 는 소유 앱 연동 시 확장 — 여기서 가짜 실적 만들지 않음)
public enum SeatOps {
    public enum Status: String, Sendable, Equatable {
        /// seats.json 에 있음
        case employed = "재직"
        /// 로스터 후보 (아직 자리 없음)
        case candidate = "후보"
    }

    public enum Category: String, CaseIterable, Sendable, Equatable, Identifiable {
        case all = "전체"
        case coordinator = "coordinator"
        case worker = "worker"
        case verifier = "verifier"
        case app = "기능"
        public var id: String { rawValue }
    }

    public struct Need: Sendable, Equatable, Identifiable {
        public var id: String { "\(kind)-\(summary)" }
        public var kind: String
        public var summary: String
        public var severity: Severity

        public init(kind: String, summary: String, severity: Severity) {
            self.kind = kind
            self.summary = summary
            self.severity = severity
        }

        public enum Severity: String, Sendable, Comparable {
            case blocker, warn, info
            public static func < (lhs: Severity, rhs: Severity) -> Bool {
                lhs.rank < rhs.rank
            }
            var rank: Int {
                switch self {
                case .blocker: return 0
                case .warn: return 1
                case .info: return 2
                }
            }
        }
    }

    public struct Activity: Sendable, Equatable {
        /// workdir 마지막 수정 (없으면 nil)
        public var workdirModifiedAt: Date?
        /// `.git/HEAD` 또는 `.git/logs/HEAD` mtime — 커밋 활동 근사치
        public var gitHeadModifiedAt: Date?
        public var seatMarkdownPresent: Bool
        public var recentFileTouches: Int
        /// 고용 후 경과 일 (floor)
        public var daysSinceHire: Int
        public var summary: String

        public init(
            workdirModifiedAt: Date?,
            gitHeadModifiedAt: Date?,
            seatMarkdownPresent: Bool,
            recentFileTouches: Int,
            daysSinceHire: Int,
            summary: String
        ) {
            self.workdirModifiedAt = workdirModifiedAt
            self.gitHeadModifiedAt = gitHeadModifiedAt
            self.seatMarkdownPresent = seatMarkdownPresent
            self.recentFileTouches = recentFileTouches
            self.daysSinceHire = daysSinceHire
            self.summary = summary
        }
    }

    public struct Feedback: Sendable, Equatable {
        public var humanNote: String?
        public var autoLines: [String]
        public var isEmpty: Bool { (humanNote?.isEmpty ?? true) && autoLines.isEmpty }

        public init(humanNote: String?, autoLines: [String]) {
            self.humanNote = humanNote
            self.autoLines = autoLines
        }
    }

    public struct Card: Sendable, Equatable, Identifiable {
        public var seat: Seat
        public var status: Status
        public var health: SeatHealth?
        public var sharedPath: Bool
        public var sharedWith: [String]
        public var needs: [Need]
        public var activity: Activity
        public var feedback: Feedback
        public var id: String { seat.handle }

        public init(
            seat: Seat,
            status: Status,
            health: SeatHealth?,
            sharedPath: Bool,
            sharedWith: [String],
            needs: [Need],
            activity: Activity,
            feedback: Feedback
        ) {
            self.seat = seat
            self.status = status
            self.health = health
            self.sharedPath = sharedPath
            self.sharedWith = sharedWith
            self.needs = needs
            self.activity = activity
            self.feedback = feedback
        }

        public var tenantKey: String { seat.keys?.tenant ?? "tenant:—" }
        /// UI 표시용 (한글 라벨). 원장 키는 `tenantKey`.
        public var tenantShort: String { SeatOps.tenantLabel(tenantKey) }
        public var category: Category {
            if !seat.occupant.isWorker { return .app }
            switch seat.limits.tier?.lowercased() {
            case "coordinator", "meta": return .coordinator
            case "verifier": return .verifier
            default: return .worker
            }
        }
        public var statusLabel: String {
            if sharedPath { return CLILocalization.string("card.status.shared") }
            if actionNeeds.contains(where: { $0.severity == .blocker }) { return "니즈 차단" }
            if health.map({ !$0.ok }) ?? false || actionNeeds.contains(where: { $0.severity == .warn }) {
                return CLILocalization.string("card.status.has_needs")
            }
            return CLILocalization.string("card.status.ready")
        }

        /// 조치가 필요한 니즈 (blocker/warn). SEAT.md 등 info 제외.
        public var actionNeeds: [Need] {
            needs.filter { $0.severity != .info }
        }

        /// 자리 파일 메모 (SEAT.md/NEEDS.md 첫 줄 등 info).
        public var fileNotes: [Need] {
            needs.filter { need in
                let isFile = need.kind == "file"
                let isInfoNonWorkspace = need.severity == .info && need.kind != "workspace"
                return isFile || isInfoNonWorkspace
            }
        }

        /// 운영 보드 정렬 키 — 차단 > 경고 > 조치 니즈 수 > 최근 활동 없음 우선.
        public var opsPriority: OpsPriority {
            let action = actionNeeds
            let last = activity.workdirModifiedAt ?? activity.gitHeadModifiedAt
            return OpsPriority(
                severity: action.map(\.severity.rank).min() ?? 9,
                needCount: -action.count,
                stale: last.map { -$0.timeIntervalSince1970 } ?? 0,
                handle: seat.handle.lowercased()
            )
        }
    }

    /// 운영 보드 정렬 키. 네 축을 순서대로 비교한다 — 이름을 붙여 둔 건 비교 순서 자체가
    /// 정책이기 때문이다(차단이 먼저, 같으면 조치 많은 자리, 그 다음 오래 방치된 자리).
    public struct OpsPriority: Sendable, Equatable, Comparable {
        public var severity: Int
        public var needCount: Int
        public var stale: TimeInterval
        public var handle: String

        public init(severity: Int, needCount: Int, stale: TimeInterval, handle: String) {
            self.severity = severity
            self.needCount = needCount
            self.stale = stale
            self.handle = handle
        }

        public static func < (a: Self, b: Self) -> Bool {
            if a.severity != b.severity { return a.severity < b.severity }
            if a.needCount != b.needCount { return a.needCount < b.needCount }
            if a.stale != b.stale { return a.stale < b.stale }
            return a.handle < b.handle
        }
    }
}
