import Foundation
import JSONLJournalKit
import StateRootKit

/// 명령어 실행 이력을 단일 JSONL 라인으로 기록하는 불변 트레이스 레코드.
public struct CommandTraceRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let tool: String
    public let command: String
    public let exitCode: Int32
    public let durationMs: Double
    public let sessionId: String?
    public let workingDirectory: String?
    public let errorSnippet: String?
    public let actor: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        tool: String,
        command: String,
        exitCode: Int32,
        durationMs: Double,
        sessionId: String? = nil,
        workingDirectory: String? = nil,
        errorSnippet: String? = nil,
        actor: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.tool = tool
        self.command = command
        self.exitCode = exitCode
        self.durationMs = durationMs
        self.sessionId = sessionId
        self.workingDirectory = workingDirectory
        self.errorSnippet = errorSnippet
        self.actor = actor
    }

    public var isSuccess: Bool {
        exitCode == 0
    }
}

/// 함대 공용 명령어 실행 저널 어댑터 (JSONLJournalKit 기반).
public final class CommandJournal: Sendable {
    public static let shared = CommandJournal()

    public static let defaultPath: String = {
        if let envPath = ProcessInfo.processInfo.environment["AGENT_COMMAND_JOURNAL_PATH"], !envPath.isEmpty {
            return (envPath as NSString).expandingTildeInPath
        }
        return StateRootKit.path(".agent-ops/ledger/commands.jsonl")
    }()

    private let journal: JSONLJournal<CommandTraceRecord>

    public init(path: String = CommandJournal.defaultPath) {
        self.journal = JSONLJournal<CommandTraceRecord>(
            path: path,
            filePermissions: 0o644,
            directoryPermissions: 0o755,
            dateCoding: .iso8601
        )
    }

    /// 단 1줄로 호출 가능한 명령어 기록 API (Fire-and-Forget, 5µs, 절대 throw 안 함)
    public static func record(
        tool: String,
        command: String,
        exitCode: Int32,
        durationMs: Double,
        sessionId: String? = nil,
        workingDirectory: String? = nil,
        errorSnippet: String? = nil,
        actor: String? = nil
    ) {
        shared.record(
            tool: tool,
            command: command,
            exitCode: exitCode,
            durationMs: durationMs,
            sessionId: sessionId,
            workingDirectory: workingDirectory,
            errorSnippet: errorSnippet,
            actor: actor
        )
    }

    public func record(
        tool: String,
        command: String,
        exitCode: Int32,
        durationMs: Double,
        sessionId: String? = nil,
        workingDirectory: String? = nil,
        errorSnippet: String? = nil,
        actor: String? = nil
    ) {
        let env = ProcessInfo.processInfo.environment
        let resolvedSessionId = sessionId
            ?? env["AGENT_SESSION_ID"]
            ?? env["CONVERSATION_ID"]
            ?? env["CLAUDE_SESSION_ID"]
        let resolvedActor = actor
            ?? env["FORGE_ACTOR"]
            ?? env["USER"]
        let resolvedCwd = workingDirectory
            ?? FileManager.default.currentDirectoryPath

        let record = CommandTraceRecord(
            tool: tool,
            command: command,
            exitCode: exitCode,
            durationMs: durationMs,
            sessionId: resolvedSessionId,
            workingDirectory: resolvedCwd,
            errorSnippet: errorSnippet,
            actor: resolvedActor
        )
        journal.append(record)
    }

    /// 최근 N건의 실행 이력 역방향 고속 로드 (0.05ms)
    public func recent(limit: Int = 100) -> [CommandTraceRecord] {
        journal.readTail(limit: limit, chronological: true)
    }

    public static func recent(limit: Int = 100) -> [CommandTraceRecord] {
        shared.recent(limit: limit)
    }

    /// kqueue 기반 실시간 스트림
    public func liveTail() -> AsyncStream<CommandTraceRecord> {
        JSONLJournalWatcher(journal: journal).liveTail()
    }

    public static func liveTail() -> AsyncStream<CommandTraceRecord> {
        shared.liveTail()
    }

    /// 프로세스 실행 완료 후 호출되는 무침습 자동 계측 훅
    internal static func autoRecordIfEnabled(
        launchPath: String,
        arguments: [String],
        exitCode: Int32,
        durationMs: Double,
        workingDirectory: URL?,
        stderr: String?
    ) {
        if ProcessInfo.processInfo.environment["COMMANDKIT_AUTO_JOURNAL"] == "0" {
            return
        }
        let toolName = URL(fileURLWithPath: launchPath).lastPathComponent
        let cmd = ([launchPath] + arguments).joined(separator: " ")
        let errSnippet: String? = {
            guard let stderr, !stderr.isEmpty, exitCode != 0 else { return nil }
            if stderr.count > 500 {
                return String(stderr.prefix(500)) + "..."
            }
            return stderr
        }()
        shared.record(
            tool: toolName,
            command: cmd,
            exitCode: exitCode,
            durationMs: durationMs,
            workingDirectory: workingDirectory?.path,
            errorSnippet: errSnippet
        )
    }
}

