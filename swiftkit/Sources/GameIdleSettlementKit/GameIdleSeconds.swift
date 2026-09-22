import Foundation

/// 방치형 정산이 다루는 "실시간 초" 의 정수 변환 규칙.
///
/// 두 선행 구현(gaya `applyOfflineProgress`, isekai `offlineSettlementSeconds`)이 모두
/// `TimeInterval` 을 그대로 `Int` 로 캐스팅하거나 곱해 오버플로 위험을 안고 있었다.
/// 여기서는 포화(saturating) 변환만 노출해 트랩을 원천 차단한다.
public enum GameIdleSeconds {
    /// `Double` 이 정수를 정확히 표현할 수 있는 최대치(2^53 - 1).
    ///
    /// `Int.max` 를 `Double` 로 올리면 반올림돼 `Int(_:)` 변환이 트랩한다. 그래서 상한을
    /// 2^53-1 로 잡는다. 이 값은 약 2억 8천만 년치 초이므로 실사용 손실은 없다.
    public static let maximumRepresentable = 9_007_199_254_740_991

    /// 초 단위 실수 구간을 내림해 음수·NaN·무한대·오버플로 없이 `Int` 로 만든다.
    ///
    /// - 유한하지 않으면(NaN·±무한대) 0
    /// - 0 이하면 0 (시계 역행 방어)
    /// - `maximumRepresentable` 이상이면 `maximumRepresentable`
    public static func saturating(_ interval: TimeInterval) -> Int {
        guard interval.isFinite, interval > 0 else { return 0 }
        if interval >= Double(maximumRepresentable) { return maximumRepresentable }
        return Int(interval.rounded(.down))
    }

    /// 오버플로 시 `Int.max` / `Int.min` 으로 포화되는 덧셈.
    public static func addingSaturating(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard overflow else { return sum }
        return rhs >= 0 ? Int.max : Int.min
    }

    /// `Date` 가 유한한 시각인지. 무한대 `Date` 는 기준선으로 저장하지 않는다.
    public static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }
}

/// 정산된 초를 "n일 n시간 n분 n초" 로 쪼갠 값.
///
/// 복귀 화면이 문자열을 직접 만들 수 있도록 계산만 제공한다(현지화는 앱 몫).
public struct GameIdleDuration: Codable, Hashable, Sendable {
    public static let secondsPerMinute = 60
    public static let secondsPerHour = 3600
    public static let secondsPerDay = 86_400

    public let totalSeconds: Int

    public init(totalSeconds: Int) {
        self.totalSeconds = max(0, totalSeconds)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(totalSeconds: try container.decode(Int.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(totalSeconds)
    }

    public var days: Int { totalSeconds / Self.secondsPerDay }
    public var hours: Int { (totalSeconds % Self.secondsPerDay) / Self.secondsPerHour }
    public var minutes: Int { (totalSeconds % Self.secondsPerHour) / Self.secondsPerMinute }
    public var seconds: Int { totalSeconds % Self.secondsPerMinute }
    public var isZero: Bool { totalSeconds == 0 }
}
