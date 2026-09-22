import Foundation
import StateRootKit

/// 파일 브리지 규약 — 에이전트(각 앱)와 허브(swift-app-devtools-hub)가 공유하는
/// 경로·포맷의 단일 정의. StateMirrorKit(`~/.swift-app-state`)·databaseviewer-sqlite
/// AgentBridge 와 같은 계열의 파일 채널이며, 여기는 devtools 전용으로
/// `~/.swift-devtools/<앱>/` 디렉터리를 쓴다.
///
/// - `heartbeat.json` — 앱 생존 신호(pid·시각). 허브가 "실행 중" 판정에 쓴다.
/// - `logs.jsonl` — 앱 자신의 OSLog tail. 한 줄 = `LogRecord` JSON 한 건.
/// - 상태(State)는 여기 중복 게시하지 않는다 — 정본은 StateMirror(`~/.swift-app-state/<앱>.json`).
public enum DevToolsBridge {
    public static var rootDir: String {
        StateRootKit.path(".swift-devtools")
    }

    public static func appDir(app: String) -> String {
        (rootDir as NSString).appendingPathComponent(app)
    }

    public static func heartbeatPath(app: String) -> String {
        (appDir(app: app) as NSString).appendingPathComponent("heartbeat.json")
    }

    public static func logsPath(app: String) -> String {
        (appDir(app: app) as NSString).appendingPathComponent("logs.jsonl")
    }

    /// 앱 생존 신호. `updatedAt` 이 오래됐거나 pid 가 죽었으면 허브는 "종료됨"으로 본다.
    public struct Heartbeat: Codable, Sendable, Equatable {
        public var app: String
        public var pid: Int32
        public var subsystem: String?
        public var startedAt: String
        public var updatedAt: String

        public init(app: String, pid: Int32, subsystem: String?, startedAt: String, updatedAt: String) {
            self.app = app
            self.pid = pid
            self.subsystem = subsystem
            self.startedAt = startedAt
            self.updatedAt = updatedAt
        }
    }

    /// `logs.jsonl` 한 줄. InspectorLog.Entry 와 같은 필드지만 Codable 로 분리 —
    /// 허브는 InspectorKit(UI 쪽 Kit)에 의존하지 않고 이 타입만 안다.
    public struct LogRecord: Codable, Sendable, Equatable {
        public var date: Date
        public var level: String
        public var category: String
        public var message: String

        public init(date: Date, level: String, category: String, message: String) {
            self.date = date
            self.level = level
            self.category = category
            self.message = message
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// JSONL 인코드 — 레코드당 한 줄, 개행 포함.
    public static func encodeLines(_ records: [LogRecord]) -> Data {
        var out = Data()
        for r in records {
            guard let line = try? encoder.encode(r) else { continue }
            out.append(line)
            out.append(0x0A)
        }
        return out
    }

    /// JSONL 디코드 — 깨진 줄은 건너뛴다(동시 쓰기 중 잘린 마지막 줄 허용).
    public static func decodeLines(_ data: Data) -> [LogRecord] {
        data.split(separator: 0x0A).compactMap { try? decoder.decode(LogRecord.self, from: $0) }
    }

    /// `logs.jsonl` 이 `maxLines` 를 넘으면 뒤쪽 `keepLines` 만 남기고 재작성한다.
    /// 파일이 무한히 크지 않게 하는 단순 캡 — 회전 로그가 아니라 최근 tail 만 정본.
    public static func cappedTail(_ records: [LogRecord], maxLines: Int, keepLines: Int) -> [LogRecord] {
        guard records.count > maxLines else { return records }
        return Array(records.suffix(keepLines))
    }
}
