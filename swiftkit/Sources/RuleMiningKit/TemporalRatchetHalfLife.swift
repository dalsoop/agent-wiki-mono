import Foundation

/// 부채 유예 반감기 및 세포자멸사(Apoptosis) 관리 엔진.
///
/// violations-ratchet.json의 ruleGates 화이트리스트에 명시된 유예 항목이
/// 보장된 반감기(Grace Period, 기본 30일)를 초과할 경우 예외를 자동 만료시키고
/// 하드 에러(Gate Failure)로 즉각 승격한다.
public enum TemporalRatchetHalfLife {
    public static let defaultGracePeriodDays: Int = 30
    public static let ruleID = "temporal-ratchet-half-life"

    public struct ExemptionHealth: Sendable, Equatable {
        public enum State: String, Sendable {
            case active
            case nearExpiry
            case expired
        }

        public let rule: String
        public let reason: String
        public let grantedAt: Date
        public let expiresAt: Date
        public let daysRemaining: Int
        public let state: State
    }

    public static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: string) { return d }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    /// ruleGates 항목의 수명 주기 분석
    public static func inspectExemption(
        rule: String,
        reason: String,
        snapshotTimestamp: String,
        evaluationDate: Date = Date(),
        gracePeriodDays: Int = defaultGracePeriodDays
    ) -> ExemptionHealth {
        let parsedGrantedAt = extractGrantedDate(from: reason)
            ?? parseDate(snapshotTimestamp)
            ?? evaluationDate

        let expiresAt = Calendar.current.date(byAdding: .day, value: gracePeriodDays, to: parsedGrantedAt)
            ?? parsedGrantedAt.addingTimeInterval(TimeInterval(gracePeriodDays * 86400))

        let remainingSeconds = expiresAt.timeIntervalSince(evaluationDate)
        let daysRemaining = Int(floor(remainingSeconds / 86400))

        let state: ExemptionHealth.State
        if remainingSeconds <= 0 {
            state = .expired
        } else if daysRemaining <= 7 {
            state = .nearExpiry
        } else {
            state = .active
        }

        return ExemptionHealth(
            rule: rule,
            reason: reason,
            grantedAt: parsedGrantedAt,
            expiresAt: expiresAt,
            daysRemaining: daysRemaining,
            state: state
        )
    }

    /// 사유 텍스트 내 메타데이터 태그 ([since: 2026-08-15]) 추출
    private static func extractGrantedDate(from reason: String) -> Date? {
        let pattern = #"(?:since|granted|date):\s*([0-9]{4}-[0-9]{2}-[0-9]{2}(?:T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsRange = NSRange(reason.startIndex..<reason.endIndex, in: reason)
        guard let match = regex.firstMatch(in: reason, options: [], range: nsRange),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: reason)
        else { return nil }

        let dateString = String(reason[range])
        if dateString.contains("T") {
            return parseDate(dateString)
        }
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        return dayFormatter.date(from: dateString)
    }

    /// 만료된 유예 항목을 필터링하여 유효한 면제 목록만 반환 (세포자멸사 적용)
    public static func pruneExpiredExemptions<T>(
        from gates: [(rule: String, reason: String, item: T)],
        snapshotTimestamp: String,
        evaluationDate: Date = Date(),
        gracePeriodDays: Int = defaultGracePeriodDays
    ) -> (active: [T], expired: [ExemptionHealth]) {
        var active: [T] = []
        var expired: [ExemptionHealth] = []

        for gate in gates {
            let health = inspectExemption(
                rule: gate.rule,
                reason: gate.reason,
                snapshotTimestamp: snapshotTimestamp,
                evaluationDate: evaluationDate,
                gracePeriodDays: gracePeriodDays
            )
            if health.state == .expired {
                expired.append(health)
            } else {
                active.append(gate.item)
            }
        }
        return (active, expired)
    }
}
