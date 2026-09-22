import Foundation

/// 3포인트 미니멀 타임라인 마일스톤 모델
/// 복잡한 간트차트 대신 [시작/탑승] -> [D-3 마감/방어] -> [종료/정가갱신] 핵심 3단계만 추적
public struct OpportunityMilestone: Sendable, Identifiable, Equatable {
    public var id: String { phase.rawValue }
    public var phase: MilestonePhase
    public var dateString: String
    public var title: String
    public var detail: String
    public var isReached: Bool

    public enum MilestonePhase: String, Sendable, CaseIterable {
        case start = "start"
        case warning = "warning"
        case completion = "completion"
    }

    public init(
        phase: MilestonePhase,
        dateString: String,
        title: String,
        detail: String,
        isReached: Bool = false
    ) {
        self.phase = phase
        self.dateString = dateString
        self.title = title
        self.detail = detail
        self.isReached = isReached
    }
}

/// 일정 및 마감 감사(Audit) 엔진
public enum OpportunityScheduleAudit {

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "Asia/Seoul") ?? TimeZone.current
        return df
    }()

    /// 마감일까지 남은 일수 (D-Day) 계산. 마감일 없으면 nil
    public static func daysUntilDeadline(_ deadlineStr: String?, today: Date = Date()) -> Int? {
        guard let deadlineStr, let deadlineDate = dateFormatter.date(from: deadlineStr) else {
            return nil
        }
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: today)
        let startOfTarget = cal.startOfDay(for: deadlineDate)
        let diff = cal.dateComponents([.day], from: startOfToday, to: startOfTarget)
        return diff.day
    }

    /// D-Day 포맷팅 (예: "D-Day", "D-3", "D+5 (마감)")
    public static func formatDDay(_ days: Int?) -> String? {
        guard let days else { return nil }
        if days == 0 { return "D-Day" }
        if days > 0 { return "D-\(days)" }
        return "D+\(abs(days)) (마감)"
    }

    /// 기회 항목에 대한 3포인트 타임라인 마일스톤 목록 생성
    public static func generate3PointMilestones(
        firstSeen: String,
        deadline: String?,
        actualValueText: String = "혜택 개시",
        isGovGrant: Bool = false,
        today: Date = Date()
    ) -> [OpportunityMilestone] {
        let cal = Calendar.current
        let todayDate = cal.startOfDay(for: today)

        // 1. 시작 마일스톤
        let startDate = dateFormatter.date(from: firstSeen) ?? todayDate
        let startReached = todayDate >= startDate
        let start = OpportunityMilestone(
            phase: .start,
            dateString: firstSeen,
            title: isGovGrant ? "공고 개시 / 접수 시작" : "기회 개시 / 신청 시작",
            detail: actualValueText,
            isReached: startReached
        )

        // 마감일이 없으면 단일 또는 기본 마일스톤 반환
        guard let deadline, let deadlineDate = dateFormatter.date(from: deadline) else {
            return [start]
        }

        // 2. D-3 알림/방어 마일스톤
        let d3Date = cal.date(byAdding: .day, value: -3, to: deadlineDate) ?? deadlineDate
        let d3DateStr = dateFormatter.string(from: d3Date)
        let d3Reached = todayDate >= d3Date
        let warning = OpportunityMilestone(
            phase: .warning,
            dateString: d3DateStr,
            title: isGovGrant ? "D-3 서류 마감 방어" : "D-3 마감 방어 / 알림",
            detail: isGovGrant ? "제출 서류 최종 점검 및 시스템 접수 완료" : "서류 최종 검토 또는 자동결제 해지 예약",
            isReached: d3Reached
        )

        // 3. 마감/갱신 마일스톤
        let endReached = todayDate >= deadlineDate
        let completion = OpportunityMilestone(
            phase: .completion,
            dateString: deadline,
            title: isGovGrant ? "공고 접수 마감" : "공고 접수 마감 / 정가 갱신",
            detail: isGovGrant ? "접수 마감 및 선정 평가 심사 착수" : "접수 마감 또는 다음 주기 시작",
            isReached: endReached
        )

        return [start, warning, completion]
    }
}
