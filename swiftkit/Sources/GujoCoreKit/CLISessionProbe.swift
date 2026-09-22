import Foundation
import CommandKit
import LocalizationKit

public struct CommandOutput: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let didTimeOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, didTimeOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.didTimeOut = didTimeOut
    }
}

public enum CLISessionProvider: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }

    public var executableName: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        }
    }

    public var statusArguments: [String] {
        switch self {
        case .codex: ["login", "status"]
        case .claude: [
            "--mcp-config", #"{"mcpServers":{}}"#,
            "--strict-mcp-config",
            "auth", "status",
        ]
        }
    }

    public var loginArguments: [String] {
        switch self {
        case .codex: ["login"]
        case .claude: ["auth", "login"]
        }
    }

    public var loginShellCommand: String {
        ([executableName] + loginArguments).joined(separator: " ")
    }
}

public enum CLISessionState: Equatable, Sendable {
    case unknown
    case notInstalled
    case unauthenticated
    case authenticated
}

public struct CLISessionStatus: Equatable, Identifiable, Sendable {
    public let provider: CLISessionProvider
    public let state: CLISessionState
    public let executablePath: String?
    public let message: String

    public var id: CLISessionProvider { provider }

    public init(provider: CLISessionProvider, state: CLISessionState, executablePath: String?, message: String) {
        self.provider = provider
        self.state = state
        self.executablePath = executablePath
        self.message = message
    }
}

public struct CLISessionProbe: Sendable {
    private let runner: @Sendable (String, [String]) async -> CommandOutput

    public init() {
        self.runner = { command, arguments in
            await CLISessionProbe.runProcess(command: command, arguments: arguments)
        }
    }

    public init(_ runner: @escaping @Sendable (String, [String]) async -> CommandOutput) {
        self.runner = runner
    }

    public func statuses() async -> [CLISessionStatus] {
        var out: [CLISessionStatus] = []
        for provider in CLISessionProvider.allCases {
            out.append(await status(for: provider))
        }
        return out
    }

    public func status(for provider: CLISessionProvider) async -> CLISessionStatus {
        let lookup = await runner("/usr/bin/which", [provider.executableName])
        guard lookup.exitCode == 0, let executablePath = firstLine(in: lookup.stdout) else {
            return CLISessionStatus(
                provider: provider,
                state: .notInstalled,
                executablePath: nil,
                message: CLILocalization.format("CLISessionProbe.message", provider.executableName)
            )
        }

        let output = await runner(executablePath, provider.statusArguments)
        if output.didTimeOut {
            return CLISessionStatus(
                provider: provider,
                state: .unknown,
                executablePath: executablePath,
                message: CLILocalization.string("CLISessionProbe.message-2")
            )
        }
        if output.exitCode == 0 {
            return CLISessionStatus(
                provider: provider,
                state: .authenticated,
                executablePath: executablePath,
                message: CLILocalization.string("session.msg.logged_in")
            )
        }

        if looksUnauthenticated(output) {
            return CLISessionStatus(
                provider: provider,
                state: .unauthenticated,
                executablePath: executablePath,
                message: CLILocalization.string("session.msg.login_needed")
            )
        }

        return CLISessionStatus(
            provider: provider,
            state: .unknown,
            executablePath: executablePath,
            message: CLILocalization.string("session.msg.status_unknown")
        )
    }

    private func firstLine(in text: String) -> String? {
        text.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    private func looksUnauthenticated(_ output: CommandOutput) -> Bool {
        let text = "\(output.stdout)\n\(output.stderr)".lowercased()
        return text.contains("not logged")
            || text.contains("not authenticated")
            || text.contains("not signed")
            || text.contains("login")
            || text.contains("log in")
            || text.contains("sign in")
    }

    static func runProcess(
        command: String,
        arguments: [String],
        timeout: TimeInterval = 5
    ) async -> CommandOutput {
        let started = Date()
        let result = await ProcessCommandRunner().run(command, arguments, timeout: timeout)
        let elapsed = Date().timeIntervalSince(started)
        let didTimeOut = elapsed >= timeout && result.exitCode != 0
        return CommandOutput(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            didTimeOut: didTimeOut
        )
    }
}

