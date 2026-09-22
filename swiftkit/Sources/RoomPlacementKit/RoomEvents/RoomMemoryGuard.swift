import Foundation

/// 닫힌 포크는 기억이다. 시간을 되돌리지 않는다.
///
/// `events.jsonl`에 `closed`가 한 줄이라도 있으면 그 방의 원장·spec·인지 기록은
/// 읽기만 허용한다. 후임은 새 현재 방을 연다.
public enum RoomMemoryGuard: Sendable {
    public static let freezeKind = RoomEventKind.closed

    public static func isFrozen(events: [RoomEvent]) -> Bool {
        events.contains { $0.kind == freezeKind }
    }

    public static func isFrozen(roomURL: URL) -> Bool {
        RoomEventLog(roomURL: roomURL).containsKind(freezeKind)
    }

    public static func assertMutable(roomURL: URL) throws {
        if isFrozen(roomURL: roomURL) {
            throw RoomEventLogError.memoryRoomFrozen
        }
    }

    /// spec.json 덮어쓰기. 기억 방이면 거절한다. 파일이 없을 때의 최초 생성도 같은 가드.
    public static func writeSpec(roomURL: URL, data: Data) throws {
        try assertMutable(roomURL: roomURL)
        let url = roomURL.appendingPathComponent(RoomPaths.specFileName, isDirectory: false)
        try FileManager.default.createDirectory(
            at: roomURL,
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
