import Foundation

/// 방 벽 프리셋 — `readOnly` < `toolbelt` < `open`. 자식은 부모보다 넓을 수 없다.
public enum RoomWallPreset: String, Codable, Sendable, CaseIterable, Comparable {
    case readOnly
    case toolbelt
    case open

    /// toolbelt·readOnly 프리셋의 도구 개수 상한. `open` 은 상한 없음.
    public static let toolbeltLimit = 6

    public var rank: Int {
        switch self {
        case .readOnly: return 0
        case .toolbelt: return 1
        case .open: return 2
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rank < rhs.rank
    }

    public func allowsToolbeltCount(_ n: Int) -> Bool {
        switch self {
        case .open:
            return true
        case .readOnly, .toolbelt:
            return n <= Self.toolbeltLimit
        }
    }

    public static func childExceedsParent(child: RoomWallPreset, parent: RoomWallPreset) -> Bool {
        child > parent
    }
}
