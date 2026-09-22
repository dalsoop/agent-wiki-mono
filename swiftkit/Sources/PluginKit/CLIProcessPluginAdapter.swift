import Foundation
import InteropKit
import StateMirrorKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if !os(iOS)
private final class SafeDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    
    func append(_ d: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(d)
    }
    
    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
#endif

/// 외부 CLI 바이너리를 `AppPlugin` (Interop Adapter) 규약으로 래핑하는 실행기.
/// 64KB 파이프 데드락 방지, 안전한 SIGTERM/SIGKILL 및 타임아웃 워치독을 지원합니다.
public final class CLIProcessPluginAdapter: AppPlugin, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let actions: [String]
    public let dependencies: [String]
    public let executablePath: String
    
    public init(
        id: String,
        name: String,
        version: String = "1.0.0",
        actions: [String] = [],
        capabilities: [String]? = nil,
        dependencies: [String] = [],
        executablePath: String
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.actions = capabilities ?? actions
        self.dependencies = dependencies
        self.executablePath = executablePath
    }
    
    /// 채널 1: StateMirrorKit 정본 경로(~/.swift-app-state/<id>.json) 직독 (0ms)
    public func readFastState(context: PluginExecutionContext = .current) -> [String: Sendable]? {
        let mirrorPath = StateMirror.path(app: id)
        guard FileManager.default.fileExists(atPath: mirrorPath),
              let data = FileManager.default.contents(atPath: mirrorPath) else {
            return nil
        }
        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Sendable]
            return json
        } catch {
            return nil
        }
    }
    
    /// 채널 2: 격리 서브프로세스로 순정 CLI 서브커맨드 실행 (비동기 파이프 드레인 + SIGKILL 워치독)
    public func execute(
        action: String,
        argv: [String] = [],
        context: PluginExecutionContext = .current,
        timeoutSeconds: Double = 30.0
    ) async throws -> [String: Sendable] {
        #if os(iOS)
        throw PluginError.executionFailed(pluginId: id, reason: "iOS 환경에서는 외부 프로세스 실행이 지원되지 않습니다.")
        #else
        try await runSubprocess(
            action: action,
            argv: argv,
            context: context,
            timeoutSeconds: timeoutSeconds
        )
        #endif
    }
    
    public func execute(action: String, argv: [String]) async throws -> [String: Sendable] {
        try await execute(action: action, argv: argv, context: .current, timeoutSeconds: 30.0)
    }

    #if !os(iOS)
    private static func terminateProcessSafely(_ process: Process, pid: Int32) {
        guard pid > 0 else { return }
        process.terminate()
        #if canImport(Darwin) || canImport(Glibc)
        kill(pid, SIGTERM)
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
            guard process.isRunning else { return }
            kill(pid, SIGKILL)
        }
        #endif
    }

    private static func drainPipes(
        stdout: Pipe,
        stderr: Pipe,
        stdoutBuf: SafeDataBuffer,
        stderrBuf: SafeDataBuffer,
        group: DispatchGroup
    ) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdoutBuf.append(stdout.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrBuf.append(stderr.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
    }

    private func runSubprocess(
        action: String,
        argv: [String],
        context: PluginExecutionContext,
        timeoutSeconds: Double
    ) async throws -> [String: Sendable] {
        guard actions.contains(action) || actions.isEmpty else {
            throw PluginError.actionNotFound(action: action, pluginId: id)
        }
        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw PluginError.executionFailed(pluginId: id, reason: "실행 바이너리가 존재하지 않습니다: \(executablePath)")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [action] + argv
        process.environment = context.makeEnvironment()
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let stdoutBuf = SafeDataBuffer()
                let stderrBuf = SafeDataBuffer()
                let group = DispatchGroup()
                
                Self.drainPipes(stdout: stdoutPipe, stderr: stderrPipe, stdoutBuf: stdoutBuf, stderrBuf: stderrBuf, group: group)
                
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: PluginError.executionFailed(pluginId: id, reason: "프로세스 실행 실패: \(error.localizedDescription)"))
                    return
                }
                
                let pid = process.processIdentifier
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
                timer.schedule(deadline: .now() + timeoutSeconds)
                timer.setEventHandler {
                    guard process.isRunning else { return }
                    Self.terminateProcessSafely(process, pid: pid)
                }
                timer.resume()
                
                process.terminationHandler = { proc in
                    timer.cancel()
                    _ = group.wait(timeout: .now() + 2.0)
                    let finalOut = stdoutBuf.get()
                    let finalErr = stderrBuf.get()
                    do {
                        let parsed = try self.parseExecutionOutput(status: proc.terminationStatus, stdout: finalOut, stderr: finalErr)
                        continuation.resume(returning: parsed)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            guard process.isRunning else { return }
            Self.terminateProcessSafely(process, pid: process.processIdentifier)
        }
    }

    private func parseExecutionOutput(status: Int32, stdout: Data, stderr: Data) throws -> [String: Sendable] {
        guard status == 0 else {
            let errStr = String(data: stderr, encoding: .utf8) ?? ""
            throw PluginError.executionFailed(pluginId: id, reason: "Exit \(status): \(errStr)")
        }
        
        do {
            let resultAny = try Envelope.parseObject(stdout)
            guard let dict = resultAny as? [String: Sendable] else {
                return ["status": "ok", "rawResult": "\(String(describing: resultAny))"]
            }
            return dict
        } catch let envErr {
            do {
                guard let rawJson = try JSONSerialization.jsonObject(with: stdout) as? [String: Sendable] else {
                    let outStr = String(data: stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return ["status": "ok", "rawOutput": outStr]
                }
                return rawJson
            } catch let jsonErr {
                _ = "\(envErr) \(jsonErr)"
                let outStr = String(data: stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return ["status": "ok", "rawOutput": outStr]
            }
        }
    }
    #endif
    
    public static func fromCapabilities(cliPath: String) throws -> CLIProcessPluginAdapter {
        #if os(iOS)
        throw PluginError.executionFailed(pluginId: cliPath, reason: "iOS 환경에서는 외부 프로세스 실행이 지원되지 않습니다.")
        #else
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["capabilities", "--json"]
        
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        
        let caps: Capabilities
        do {
            let resultAny = try Envelope.parseObject(data)
            let rawData = try JSONSerialization.data(withJSONObject: resultAny)
            caps = try JSONDecoder().decode(Capabilities.self, from: rawData)
        } catch {
            caps = try JSONDecoder().decode(Capabilities.self, from: data)
        }
        
        let actions = caps.commands.map { $0.name }
        return CLIProcessPluginAdapter(
            id: caps.cli,
            name: caps.name,
            version: caps.version,
            actions: actions,
            dependencies: caps.depends.map { $0.id },
            executablePath: cliPath
        )
        #endif
    }
}
