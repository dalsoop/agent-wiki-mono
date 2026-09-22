import CommandKit
import Foundation
import StateRootKit

public struct SandboxExecutionResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool { exitCode == 0 }

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// 샌드박스 내부에서 커널 격리 및 프로세스 실행을 주관하는 러너.
public enum SandboxRunner {
    public static let defaultTimeout: TimeInterval = 120

    /// 샌드박스 컨텍스트 안에서 명령을 실행한다.
    public static func run(
        executable: String,
        arguments: [String] = [],
        context: SandboxContext,
        applySeatbelt: Bool = true,
        extraAllowedPaths: [String] = [],
        timeout: TimeInterval = defaultTimeout
    ) throws -> SandboxExecutionResult {
        let env = context.makeEnvironment()
        let launch: String
        let argv: [String]

        #if os(macOS)
        let sandboxExecPath = "/usr/bin/sandbox-exec"
        let canApplySeatbelt = applySeatbelt && FileManager.default.isExecutableFile(atPath: sandboxExecPath)
        if canApplySeatbelt {
            let profile = context.generateProfile(extraAllowedPaths: extraAllowedPaths)
            launch = sandboxExecPath
            argv = ["-p", profile.generateScheme(), executable] + arguments
        } else {
            launch = executable
            argv = arguments
        }
        #else
        launch = executable
        argv = arguments
        #endif

        let startTime = Date()
        let envPairs = env.map { key, value in
            "\(key)=\(value.replacingOccurrences(of: "\0", with: ""))"
        }
        let result = CommandKitSync.run(
            "/usr/bin/env",
            envPairs + [launch] + argv,
            timeout: timeout
        )
        let durationMs = Date().timeIntervalSince(startTime) * 1000.0

        let historyCount = try FlightRecorder.readHistory(context: context).count
        let record = FlightRecord(
            roomID: context.roomID,
            tenant: context.tenantSlug,
            agentID: context.agentID,
            stepIndex: historyCount + 1,
            timestamp: startTime,
            executable: executable,
            arguments: arguments,
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            durationMs: durationMs
        )
        try FlightRecorder.record(event: record, context: context)

        return SandboxExecutionResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }

    /// 일회성(One-Shot) 샌드박스를 띄워 작업을 수행하고 완료 시 100% 자동 회수한다 (동기).
    public static func withOneShotSandbox<T>(
        tenant: String,
        agentID: String? = nil,
        roomID: String? = nil,
        homeDirectory: String = StateRootKit.resolveHost(environment: [:]),
        block: (SandboxContext) throws -> T
    ) throws -> T {
        let context = try SandboxContext.allocate(
            tenant: tenant,
            agentID: agentID,
            roomID: roomID,
            homeDirectory: homeDirectory
        )
        do {
            let value = try block(context)
            try context.teardown()
            return value
        } catch {
            Self.logTeardownFailure(of: context, prefix: "withOneShotSandbox")
            throw error
        }
    }

    /// 일회성(One-Shot) 샌드박스를 띄워 작업을 수행하고 완료 시 100% 자동 회수한다 (비동기).
    public static func withOneShotSandboxAsync<T>(
        tenant: String,
        agentID: String? = nil,
        roomID: String? = nil,
        homeDirectory: String = StateRootKit.resolveHost(environment: [:]),
        block: (SandboxContext) async throws -> T
    ) async throws -> T {
        let context = try SandboxContext.allocate(
            tenant: tenant,
            agentID: agentID,
            roomID: roomID,
            homeDirectory: homeDirectory
        )
        do {
            let value = try await block(context)
            try context.teardown()
            return value
        } catch {
            Self.logTeardownFailure(of: context, prefix: "withOneShotSandboxAsync")
            throw error
        }
    }

    private static func logTeardownFailure(of context: SandboxContext, prefix: String) {
        do {
            try context.teardown()
        } catch {
            fputs("SandboxKit \(prefix) teardown failed: \(error.localizedDescription)\n", stderr)
        }
    }
}
