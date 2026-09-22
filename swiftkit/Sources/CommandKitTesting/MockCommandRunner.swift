import Foundation
import os
import CommandKit
#if canImport(XCTest)
import XCTest
#endif

/// 명령 명세(`CommandSpecification`) 매칭 규칙을 정의하는 매처.
public struct CommandMatcher: Sendable {
    public let predicate: @Sendable (CommandSpecification) -> Bool

    public init(predicate: @escaping @Sendable (CommandSpecification) -> Bool) {
        self.predicate = predicate
    }

    public func matches(_ spec: CommandSpecification) -> Bool {
        predicate(spec)
    }

    /// 모든 명령과 매칭.
    public static var any: CommandMatcher {
        CommandMatcher { _ in true }
    }

    /// 실행 경로와 인자가 정확히 일치하는지 검사.
    public static func exact(launchPath: String, arguments: [String] = []) -> CommandMatcher {
        CommandMatcher { spec in
            spec.launchPath == launchPath && spec.arguments == arguments
        }
    }

    /// 실행 파일 이름(경로 마지막 컴포넌트) 또는 전체 경로가 일치하는지 검사.
    public static func executable(_ name: String) -> CommandMatcher {
        CommandMatcher { spec in
            spec.launchPath == name || (spec.launchPath as NSString).lastPathComponent == name
        }
    }

    /// 실행 파일 경로에 특정 문자열이 포함되는지 검사.
    public static func launchPathContains(_ substring: String) -> CommandMatcher {
        CommandMatcher { spec in
            spec.launchPath.contains(substring)
        }
    }

    /// 명령행 인자 목록이 일치하는지 검사.
    public static func argumentsEqual(_ args: [String]) -> CommandMatcher {
        CommandMatcher { spec in
            spec.arguments == args
        }
    }

    /// 특정 명령행 인자가 포함되어 있는지 검사.
    public static func argumentsContain(_ arg: String) -> CommandMatcher {
        CommandMatcher { spec in
            spec.arguments.contains(arg)
        }
    }

    /// 명령행 인자가 지정된 접두사로 시작하는지 검사.
    public static func argumentsPrefix(_ prefix: [String]) -> CommandMatcher {
        CommandMatcher { spec in
            spec.arguments.starts(with: prefix)
        }
    }

    /// 모든 조건이 참이어야 매칭 (AND).
    public static func all(_ matchers: CommandMatcher...) -> CommandMatcher {
        CommandMatcher { spec in
            matchers.allSatisfy { $0.matches(spec) }
        }
    }

    /// 하나 이상의 조건이 참이면 매칭 (OR).
    public static func anyOf(_ matchers: CommandMatcher...) -> CommandMatcher {
        CommandMatcher { spec in
            matchers.contains { $0.matches(spec) }
        }
    }

    /// 조건 반전 (NOT).
    public static func not(_ matcher: CommandMatcher) -> CommandMatcher {
        CommandMatcher { spec in
            !matcher.matches(spec)
        }
    }
}

/// 실행된 명령의 기록.
public struct CommandInvocation: Sendable, Equatable, CustomStringConvertible {
    public let spec: CommandSpecification
    public let timestamp: Date

    public init(spec: CommandSpecification, timestamp: Date = Date()) {
        self.spec = spec
        self.timestamp = timestamp
    }

    public var launchPath: String { spec.launchPath }
    public var arguments: [String] { spec.arguments }
    public var environment: [String: String]? { spec.environment }
    public var workingDirectory: URL? { spec.workingDirectory }
    public var input: Data? { spec.input }
    public var timeout: TimeInterval? { spec.timeout }

    public var description: String {
        spec.description
    }
}

/// 목 러너에서 반환할 스텁 정의.
public struct CommandStub: Sendable {
    public let matcher: CommandMatcher
    public let handler: @Sendable (CommandSpecification) async throws -> CommandResult
    public let streamHandler: (@Sendable (CommandSpecification) -> [CommandLineOutput])?

    public init(
        matcher: CommandMatcher,
        handler: @escaping @Sendable (CommandSpecification) async throws -> CommandResult,
        streamHandler: (@Sendable (CommandSpecification) -> [CommandLineOutput])? = nil
    ) {
        self.matcher = matcher
        self.handler = handler
        self.streamHandler = streamHandler
    }
}

/// 스레드 안전한 테스트용 `CommandRunning` Mock 러너.
///
/// 호출 이력(`calls`)을 기록하고, `CommandMatcher` 기반의 스텁 응답을 제공하며,
/// `assertCalled`, `assertNotCalled` 등의 검증 메서드를 제공한다.
public final class MockCommandRunner: CommandRunning, Sendable {
    private struct State: Sendable {
        var calls: [CommandInvocation] = []
        var stubs: [CommandStub] = []
        var defaultResult: CommandResult
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(defaultResult: CommandResult = CommandResult(stdout: "", stderr: "", exitCode: 0)) {
        self.state = OSAllocatedUnfairLock(initialState: State(defaultResult: defaultResult))
    }

    // MARK: - Stubbing API

    /// 특정 매처에 대해 고정된 `CommandResult` 결과를 스텁한다.
    public func stub(
        matcher: CommandMatcher,
        result: CommandResult,
        streamOutputs: [CommandLineOutput]? = nil
    ) {
        let streamHandler: (@Sendable (CommandSpecification) -> [CommandLineOutput])?
        if let streamOutputs {
            streamHandler = { _ in streamOutputs }
        } else {
            streamHandler = nil
        }
        let stub = CommandStub(
            matcher: matcher,
            handler: { _ in result },
            streamHandler: streamHandler
        )
        state.withLock { s in
            s.stubs.append(stub)
        }
    }

    /// 특정 매처에 대해 stdout, stderr, exitCode로 스텁한다.
    public func stub(
        matcher: CommandMatcher,
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32 = 0
    ) {
        stub(matcher: matcher, result: CommandResult(stdout: stdout, stderr: stderr, exitCode: exitCode))
    }

    /// 실행 파일 이름(또는 경로)으로 스텁한다.
    public func stub(
        executable: String,
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32 = 0
    ) {
        stub(matcher: .executable(executable), stdout: stdout, stderr: stderr, exitCode: exitCode)
    }

    /// 실행 파일 이름과 인자 목록으로 스텁한다.
    public func stub(
        executable: String,
        arguments: [String],
        stdout: String = "",
        stderr: String = "",
        exitCode: Int32 = 0
    ) {
        stub(
            matcher: .all(.executable(executable), .argumentsEqual(arguments)),
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode
        )
    }

    /// 특정 매처에 대해 에러를 던지도록 스텁한다.
    public func stubError(
        matcher: CommandMatcher,
        error: Error
    ) {
        let stub = CommandStub(
            matcher: matcher,
            handler: { _ in throw error },
            streamHandler: nil
        )
        state.withLock { s in
            s.stubs.append(stub)
        }
    }

    /// 동적 핸들러를 등록하여 요청 명세에 따라 계산된 결과를 반환하도록 스텁한다.
    public func stubHandler(
        matcher: CommandMatcher,
        handler: @escaping @Sendable (CommandSpecification) async throws -> CommandResult
    ) {
        let stub = CommandStub(
            matcher: matcher,
            handler: handler,
            streamHandler: nil
        )
        state.withLock { s in
            s.stubs.append(stub)
        }
    }

    /// 기본 반환 결과를 설정한다.
    public func setDefaultResult(_ result: CommandResult) {
        state.withLock { s in
            s.defaultResult = result
        }
    }

    // MARK: - History API

    /// 누적된 모든 호출 기록.
    public var calls: [CommandInvocation] {
        state.withLock { $0.calls }
    }

    /// 누적된 모든 명령 명세 목록.
    public var specifications: [CommandSpecification] {
        state.withLock { $0.calls.map(\.spec) }
    }

    /// 호출된 횟수.
    public var callCount: Int {
        state.withLock { $0.calls.count }
    }

    /// 호출 기록만 초기화한다.
    public func clearCalls() {
        state.withLock { s in
            s.calls.removeAll()
        }
    }

    /// 호출 기록과 스텁을 모두 초기화한다.
    public func reset() {
        state.withLock { s in
            s.calls.removeAll()
            s.stubs.removeAll()
            s.defaultResult = CommandResult(stdout: "", stderr: "", exitCode: 0)
        }
    }

    // MARK: - CommandRunning Implementation

    public func run(_ spec: CommandSpecification) async -> CommandResult {
        let invocation = CommandInvocation(spec: spec)
        let (matchedStub, fallback) = state.withLock { s -> (CommandStub?, CommandResult) in
            s.calls.append(invocation)
            let stub = s.stubs.reversed().first { $0.matcher.matches(spec) }
            return (stub, s.defaultResult)
        }

        if let matchedStub {
            do {
                return try await matchedStub.handler(spec)
            } catch {
                return CommandResult(stdout: "", stderr: error.localizedDescription, exitCode: 127)
            }
        }
        return fallback
    }

    public func lines(_ spec: CommandSpecification) -> AsyncThrowingStream<CommandLineOutput, Error> {
        let invocation = CommandInvocation(spec: spec)
        let (matchedStub, fallback) = state.withLock { s -> (CommandStub?, CommandResult) in
            s.calls.append(invocation)
            let stub = s.stubs.reversed().first { $0.matcher.matches(spec) }
            return (stub, s.defaultResult)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                switch matchedStub {
                case .some(let stub) where stub.streamHandler != nil:
                    guard let streamHandler = stub.streamHandler else {
                        continuation.finish()
                        return
                    }
                    for output in streamHandler(spec) {
                        continuation.yield(output)
                    }
                    continuation.finish()
                case .some(let stub):
                    do {
                        let result = try await stub.handler(spec)
                        guard !Task.isCancelled else {
                            continuation.finish(throwing: CancellationError())
                            return
                        }
                        Self.yieldResultLines(result, into: continuation, spec: spec)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                case .none:
                    Self.yieldResultLines(fallback, into: continuation, spec: spec)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        await run(CommandSpecification(launchPath, arguments, timeout: timeout))
    }

    private static func yieldResultLines(
        _ result: CommandResult,
        into continuation: AsyncThrowingStream<CommandLineOutput, Error>.Continuation,
        spec: CommandSpecification
    ) {
        let stdout = result.stdout.hasSuffix("\n") ? String(result.stdout.dropLast()) : result.stdout
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: false) where !stdout.isEmpty {
            continuation.yield(.stdout(String(line)))
        }
        let stderr = result.stderr.hasSuffix("\n") ? String(result.stderr.dropLast()) : result.stderr
        for line in stderr.split(separator: "\n", omittingEmptySubsequences: false) where !stderr.isEmpty {
            continuation.yield(.stderr(String(line)))
        }
        switch (result.timedOut, result.exitCode) {
        case (true, _):
            continuation.finish(throwing: CommandError.timedOut(spec.timeout ?? 0))
        case (false, let code) where code != 0:
            continuation.finish(throwing: CommandError.nonZeroExit(exitCode: code, stderr: result.stderr))
        default:
            continuation.finish()
        }
    }

    // MARK: - Assertion Helpers

    /// 주어진 매처에 부합하는 명령이 호출되었는지 검증한다.
    @discardableResult
    public func assertCalled(
        matcher: CommandMatcher,
        times: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let matchingCalls = calls.filter { matcher.matches($0.spec) }
        let count = matchingCalls.count
        let success: Bool
        let message: String

        if let times {
            success = (count == times)
            message = "Expected \(times) calls matching matcher, but found \(count)."
        } else {
            success = (count > 0)
            message = "Expected at least 1 call matching matcher, but found 0."
        }

        if !success {
            #if canImport(XCTest)
            XCTFail(message, file: file, line: line)
            #endif
            return false
        }
        return true
    }

    /// 특정 실행 파일명 및 인자로 호출되었는지 검증한다.
    @discardableResult
    public func assertCalled(
        executable: String,
        arguments: [String]? = nil,
        times: Int? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let matcher: CommandMatcher
        if let arguments {
            matcher = .all(.executable(executable), .argumentsEqual(arguments))
        } else {
            matcher = .executable(executable)
        }
        return assertCalled(matcher: matcher, times: times, file: file, line: line)
    }

    /// 주어진 매처에 부합하는 명령이 전혀 호출되지 않았는지 검증한다.
    @discardableResult
    public func assertNotCalled(
        matcher: CommandMatcher,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let count = calls.filter { matcher.matches($0.spec) }.count
        if count > 0 {
            let message = "Expected no calls matching matcher, but found \(count)."
            #if canImport(XCTest)
            XCTFail(message, file: file, line: line)
            #endif
            return false
        }
        return true
    }

    /// 특정 실행 파일이 전혀 호출되지 않았는지 검증한다.
    @discardableResult
    public func assertNotCalled(
        executable: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        assertNotCalled(matcher: .executable(executable), file: file, line: line)
    }

    /// 총 호출 횟수가 일치하는지 검증한다.
    @discardableResult
    public func assertCallCount(
        _ expectedCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let actual = callCount
        if actual != expectedCount {
            let message = "Expected \(expectedCount) total calls, but found \(actual)."
            #if canImport(XCTest)
            XCTFail(message, file: file, line: line)
            #endif
            return false
        }
        return true
    }
}
