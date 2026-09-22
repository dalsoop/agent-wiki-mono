import Foundation

/// 데몬이 발급하는 방 세션 식별자.
///
/// ## 계약
/// - PID·argv 로 세션 생존을 판정하지 않는다. sessionID 는 exec 래퍼·샌드박스 백엔드와 무관하게 유지된다.
/// - 형식은 `"pty-<UUID>"` 또는 `"exec-<UUID>"` 이며, 한 번 발급된 값은 세션 생애 동안 불변이다.
/// - 데몬 세션 목록 CLI(`daemon sessions --json`)는 방마다 `{roomID, sessionID, state}` 를 출력한다.
/// - seatbelt 백엔드로 감싼 세션과 srt 백엔드로 감싼 세션은 같은 sessionID 형식·같은 이벤트 페이로드를 낸다.
public struct RoomSessionID: Hashable, Sendable, CustomStringConvertible {
    /// 데몬이 발급한 불투명 문자열 값
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    /// PTY 세션용 식별자를 새로 발급한다.
    public static func newPty() -> RoomSessionID {
        RoomSessionID("pty-\(UUID().uuidString.lowercased())")
    }

    /// Exec 세션용 식별자를 새로 발급한다.
    public static func newExec() -> RoomSessionID {
        RoomSessionID("exec-\(UUID().uuidString.lowercased())")
    }

    public var description: String { value }
}

extension RoomSessionID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
