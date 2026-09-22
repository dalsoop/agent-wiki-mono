import Foundation

/// 상대 시간 버킷. UI 가 언어별 포맷 문자열에 끼워 넣는다.
public enum RelativeTime {
    public enum Bucket: Equatable, Sendable {
        case none
        case justNow
        case seconds(Int)
        case minutes(Int)
        case hours(Int)
        case days(Int)
    }

    public static func bucket(_ date: Date?, now: Date = Date()) -> Bucket {
        guard let date else { return .none }
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 0 { return .justNow }
        switch seconds {
        case 0..<60: return .seconds(seconds)
        case 60..<3600: return .minutes(seconds / 60)
        case 3600..<86_400: return .hours(seconds / 3600)
        default: return .days(seconds / 86_400)
        }
    }

    public static func short(_ date: Date?, now: Date = Date()) -> String {
        switch bucket(date, now: now) {
        case .none: return "—"
        case .justNow: return "just now"
        case .seconds(let s): return "\(s)s ago"
        case .minutes(let m): return "\(m)m ago"
        case .hours(let h): return "\(h)h ago"
        case .days(let d): return "\(d)d ago"
        }
    }
}
