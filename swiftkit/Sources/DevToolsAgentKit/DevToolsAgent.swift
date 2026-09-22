import Foundation
import OSLog

/// 앱 안에 심는 UI 없는 devtools 에이전트. 앱 루트에서 한 줄이면 끝:
/// ```swift
/// DevToolsAgent.start(app: "pim-mail", subsystem: "net.ranode.pim-mail")
/// ```
/// 이후 2초마다 자기 프로세스의 OSLog 를 `~/.swift-devtools/<앱>/logs.jsonl` 로
/// 퍼올리고 `heartbeat.json` 을 갱신한다. 허브 앱(swift-app-devtools-hub)이 이
/// 디렉터리를 읽어 100개 앱을 한 화면에서 보여준다.
///
/// 타 프로세스 로그는 권한 없이 못 읽으므로(OSLogStore 는 자기 프로세스 스코프만
/// 무권한) 각 앱이 스스로 퍼올리는 이 구조가 정공법이다.
@MainActor
public final class DevToolsAgent {
    public static let shared = DevToolsAgent()

    private var pollTask: Task<Void, Never>?
    private var store: OSLogStore?
    private var lastDate: Date?
    private var app = ""
    private var subsystem: String?
    private var startedAt = ""
    private let maxLines = 1200
    private let keepLines = 800

    private init() {}

    /// 게시 시작. 중복 호출은 무시된다. `subsystem` 을 주면 그 subsystem 로그만
    /// 남긴다(매 프로세스에 섞여 들어오는 XPC/tccd 소음 제거).
    public static func start(app: String, subsystem: String? = nil, pollInterval: TimeInterval = 2) {
        shared.startPolling(app: app, subsystem: subsystem, pollInterval: pollInterval)
    }

    public static func stop() {
        shared.pollTask?.cancel()
        shared.pollTask = nil
    }

    private func startPolling(app: String, subsystem: String?, pollInterval: TimeInterval) {
        guard pollTask == nil else { return }
        self.app = app
        self.subsystem = subsystem
        startedAt = ISO8601DateFormatter().string(from: Date())
        do {
            store = try OSLogStore(scope: .currentProcessIdentifier)
        } catch {
            store = nil
        }
        do { try FileManager.default.createDirectory(
            atPath: DevToolsBridge.appDir(app: app), withIntermediateDirectories: true) } catch { _ = error }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
    }

    private func tick() {
        writeHeartbeat()
        appendNewLogs()
    }

    private func writeHeartbeat() {
        let now = ISO8601DateFormatter().string(from: Date())
        let hb = DevToolsBridge.Heartbeat(
            app: app, pid: ProcessInfo.processInfo.processIdentifier,
            subsystem: subsystem, startedAt: startedAt, updatedAt: now)
        guard let data = try? DevToolsBridge.encoder.encode(hb) else { return }
        do { try data.write(to: URL(fileURLWithPath: DevToolsBridge.heartbeatPath(app: app)), options: .atomic) } catch { _ = error }
    }

    private func appendNewLogs() {
        guard let store else { return }
        let since = lastDate ?? Date().addingTimeInterval(-60)
        let position = store.position(date: since)
        guard let entries = try? store.getEntries(at: position) else { return }
        var fresh: [DevToolsBridge.LogRecord] = []
        for entry in entries {
            guard let log = entry as? OSLogEntryLog, log.date > since else { continue }
            if let subsystem, log.subsystem != subsystem { continue }
            fresh.append(DevToolsBridge.LogRecord(
                date: log.date,
                level: levelName(log.level),
                category: log.category,
                message: log.composedMessage))
            lastDate = max(lastDate ?? .distantPast, log.date)
        }
        guard !fresh.isEmpty else { return }
        persist(appending: fresh)
    }

    private func persist(appending fresh: [DevToolsBridge.LogRecord]) {
        let path = DevToolsBridge.logsPath(app: app)
        let existing = FileManager.default.contents(atPath: path).map(DevToolsBridge.decodeLines) ?? []
        let all = DevToolsBridge.cappedTail(existing + fresh, maxLines: maxLines, keepLines: keepLines)
        if all.count < existing.count + fresh.count {
            try? DevToolsBridge.encodeLines(all)
                .write(to: URL(fileURLWithPath: path), options: .atomic)
        } else if let handle = FileHandle(forWritingAtPath: path) {
            defer { do { try handle.close() } catch {} }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: DevToolsBridge.encodeLines(fresh))
            } catch {}
        } else {
            try? DevToolsBridge.encodeLines(all)
                .write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    private func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "unknown"
        }
    }
}
