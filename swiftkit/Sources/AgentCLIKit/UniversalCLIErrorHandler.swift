import Foundation
import AppErrorKit
import ISO8601DateCodecKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - POSIX Sysexits Constants

/// POSIX `sysexits.h` 표준 종료 코드 상수 네임스페이스.
public enum POSIXSysexits {
    /// 성공 (EX_OK: 0)
    public static let ok: Int32 = 0
    /// 명령줄 사용법 오류 / 검증 실패 (EX_USAGE: 64)
    public static let usage: Int32 = 64
    /// 잘못된 입력 데이터 포맷 (EX_DATAERR: 65)
    public static let dataErr: Int32 = 65
    /// 입력 파일을 열 수 없음 (EX_NOINPUT: 66)
    public static let noInput: Int32 = 66
    /// 지정된 사용자 없음 (EX_NOUSER: 67)
    public static let noUser: Int32 = 67
    /// 지정된 호스트 없음 (EX_NOHOST: 68)
    public static let noHost: Int32 = 68
    /// 서비스 또는 원격지 사용 불가 / 설정 누락 (EX_UNAVAILABLE: 69)
    public static let unavailable: Int32 = 69
    /// 내부 소프트웨어 결함 (EX_SOFTWARE: 70)
    public static let software: Int32 = 70
    /// 시스템 OS 오류 (EX_OSERR: 71)
    public static let osErr: Int32 = 71
    /// 핵심 OS 파일 누락 (EX_OSFILE: 72)
    public static let osFile: Int32 = 72
    /// 출력 파일 생성 불가 (EX_CANTCREAT: 73)
    public static let cantCreat: Int32 = 73
    /// 입출력 오류 (EX_IOERR: 74)
    public static let ioErr: Int32 = 74
    /// 일시적 실패 (EX_TEMPFAIL: 75)
    public static let tempFail: Int32 = 75
    /// 원격 프로토콜 오류 (EX_PROTOCOL: 76)
    public static let protocolErr: Int32 = 76
    /// 권한 거부됨 (EX_NOPERM: 77)
    public static let noPerm: Int32 = 77
    /// 환경 설정 오류 (EX_CONFIG: 78)
    public static let config: Int32 = 78
}

// MARK: - RFC 9457 Problem Details

/// RFC 9457 ("Problem Details for HTTP APIs") 표준 호환 구조체.
///
/// CLI `--json` 출력 시 기계가 신뢰하고 파싱할 수 있는 표준 에러 엔벨로프입니다.
public struct RFC9457ProblemDetails: Codable, Sendable, Equatable {
    /// 문제 유형을 식별하는 URI (RFC 9457 필수)
    public let type: String
    /// 사람이 읽을 수 있는 짧은 요약 (RFC 9457 필수)
    public let title: String
    /// HTTP 또는 Sysexits 상태 코드 (RFC 9457 필수)
    public let status: Int
    /// 구체적인 원인 및 안내 설명 (RFC 9457 필수)
    public let detail: String
    /// 특정 에러 발생 인스턴스를 식별하는 URI (RFC 9457 필수)
    public let instance: String
    /// 도메인 고유 에러 코드 (확장 필드)
    public let code: String
    /// 에러 분류 범주 (확장 필드)
    public let category: String
    /// 에러 심각도 수준 (확장 필드)
    public let severity: String
    /// 사용자 복구 제안 (확장 필드)
    public let recoverySuggestion: String?
    /// 부가 컨텍스트 맵 (확장 필드)
    public let context: [String: String]
    /// 발생 시각 ISO8601 문자열 (확장 필드)
    public let timestamp: String

    public init(
        type: String,
        title: String,
        status: Int,
        detail: String,
        instance: String,
        code: String,
        category: String,
        severity: String,
        recoverySuggestion: String? = nil,
        context: [String: String] = [:],
        timestamp: String? = nil
    ) {
        self.type = type
        self.title = title
        self.status = status
        self.detail = detail
        self.instance = instance
        self.code = code
        self.category = category
        self.severity = severity
        self.recoverySuggestion = recoverySuggestion
        self.context = context
        self.timestamp = timestamp ?? ISO8601DateCodec.format(Date())
    }

    public init(error: any AppError, status: Int? = nil) {
        let anyError = (error as? AnyAppError) ?? AnyAppError(error)
        let resolvedStatus = status ?? Int(UniversalCLIErrorHandler.sysexitsCode(for: error))
        let lowerCode = error.errorCode.lowercased().replacingOccurrences(of: "_", with: "-")
        self.type = "urn:problem:\(lowerCode)"
        self.title = error.errorCode
        self.status = resolvedStatus
        self.detail = error.userFacingMessage
        self.instance = "urn:uuid:\(anyError.id.uuidString.lowercased())"
        self.code = error.errorCode
        self.category = error.category.rawValue
        self.severity = error.severity.rawValue
        self.recoverySuggestion = error.userFacingRecoverySuggestion
        self.context = error.context
        self.timestamp = ISO8601DateCodec.format(Date())
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case title
        case status
        case detail
        case instance
        case code
        case category
        case severity
        case recoverySuggestion = "recovery_suggestion"
        case context
        case timestamp
    }
}

// MARK: - CLI Error Output Destination

/// 에러 출력 채널 대상.
public enum CLIErrorOutputDestination: Sendable {
    case standardError
    case standardOutput
    case custom(@Sendable (String) -> Void)

    public func write(_ text: String) {
        switch self {
        case .standardError:
            FileHandle.standardError.write(Data((text + "\n").utf8))
        case .standardOutput:
            FileHandle.standardOutput.write(Data((text + "\n").utf8))
        case .custom(let handler):
            handler(text)
        }
    }
}

// MARK: - Universal CLI Error Handler

public enum UniversalCLIErrorHandler: Sendable {

    /// `AppError.category`를 표준 POSIX Sysexits 종료 코드로 매핑합니다.
    public static func sysexitsCode(for error: any AppError) -> Int32 {
        switch error.category {
        case .validation:
            return POSIXSysexits.usage         // 64
        case .permission:
            return POSIXSysexits.noPerm        // 77
        case .fileSystem:
            return POSIXSysexits.ioErr         // 74
        case .network:
            return POSIXSysexits.unavailable   // 69
        case .system:
            return POSIXSysexits.osErr         // 71
        case .business:
            return POSIXSysexits.software      // 70
        case .cancelled:
            return 130                         // 128 + 2 (SIGINT)
        case .unknown:
            return POSIXSysexits.software      // 70
        }
    }

    /// 현재 환경이 TTY이고 ANSI 색상 출력이 가능한지 판별합니다.
    public static func isTTY(fileDescriptor: Int32 = STDERR_FILENO) -> Bool {
        guard isatty(fileDescriptor) != 0 else { return false }
        if let term = getenv("TERM"), String(cString: term) == "dumb" {
            return false
        }
        if getenv("NO_COLOR") != nil {
            return false
        }
        return true
    }

    /// RFC 9457 규격 JSON 문자열을 생성합니다.
    public static func formatRFC9457JSON(for error: any AppError, status: Int? = nil) -> String {
        let problem = RFC9457ProblemDetails(error: error, status: status)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(problem)
            if let json = String(data: data, encoding: .utf8) {
                return json
            }
        } catch {
            AppErrorReporter.shared.report(UniversalErrorAdapter.adapt(error))
        }
        return """
        {
          "code": "\(problem.code)",
          "detail": "\(problem.detail)",
          "instance": "\(problem.instance)",
          "status": \(problem.status),
          "title": "\(problem.title)",
          "type": "\(problem.type)"
        }
        """
    }

    private struct BoxColors {
        let bold: String
        let red: String
        let yellow: String
        let cyan: String
        let dim: String
        let reset: String
        let border: String

        init(useColor: Bool, severity: ErrorSeverity) {
            self.bold = useColor ? "\u{001B}[1m" : ""
            self.red = useColor ? "\u{001B}[1;31m" : ""
            self.yellow = useColor ? "\u{001B}[1;33m" : ""
            self.cyan = useColor ? "\u{001B}[36m" : ""
            self.dim = useColor ? "\u{001B}[2m" : ""
            self.reset = useColor ? "\u{001B}[0m" : ""
            self.border = severity == .warning ? yellow : red
        }
    }

    /// TTY용 ANSI 컬러 진단 박스(또는 Plain 박스)를 생성합니다.
    public static func formatDiagnosticBox(
        for error: any AppError,
        useColor: Bool = true,
        boxWidth: Int = 78
    ) -> String {
        let anyError = (error as? AnyAppError) ?? AnyAppError(error)
        let colors = BoxColors(useColor: useColor, severity: error.severity)
        let innerWidth = max(boxWidth - 4, 40)

        var lines: [String] = []
        appendHeader(lines: &lines, error: error, colors: colors, innerWidth: innerWidth)
        appendMessage(lines: &lines, error: error, colors: colors, innerWidth: innerWidth)
        appendCauseIfPresent(lines: &lines, error: error, anyError: anyError, colors: colors, innerWidth: innerWidth)
        appendActionIfPresent(lines: &lines, error: error, colors: colors, innerWidth: innerWidth)
        appendMetadataIfPresent(lines: &lines, error: error, colors: colors, innerWidth: innerWidth)
        appendFooter(lines: &lines, colors: colors, innerWidth: innerWidth)

        return lines.joined(separator: "\n")
    }

    private static func appendHeader(
        lines: inout [String],
        error: any AppError,
        colors: BoxColors,
        innerWidth: Int
    ) {
        let titleBadge = " [\(error.category.rawValue.uppercased())] \(error.errorCode) "
        let topBarLen = max(0, innerWidth - titleBadge.count)
        let topBar = String(repeating: "─", count: topBarLen)
        lines.append("\(colors.border)┌─\(colors.bold)\(titleBadge)\(colors.reset)\(colors.border)\(topBar)┐\(colors.reset)")
        lines.append("\(colors.border)│\(colors.reset)\(String(repeating: " ", count: innerWidth + 2))\(colors.border)│\(colors.reset)")
    }

    private static func appendMessage(
        lines: inout [String],
        error: any AppError,
        colors: BoxColors,
        innerWidth: Int
    ) {
        let messagePrefix = "Message: "
        for wrapped in wrapText(error.userFacingMessage, width: innerWidth - messagePrefix.count) {
            let content = "\(colors.bold)\(messagePrefix)\(colors.reset)\(wrapped)"
            let rawLen = messagePrefix.count + wrapped.count
            lines.append(formatBoxLine(content: content, rawLength: rawLen, innerWidth: innerWidth, borderColor: colors.border, reset: colors.reset))
        }
    }

    private static func appendCauseIfPresent(
        lines: inout [String],
        error: any AppError,
        anyError: AnyAppError,
        colors: BoxColors,
        innerWidth: Int
    ) {
        let causeDesc = anyError.underlyingErrorDescription
            ?? (error.underlyingError as? LocalizedError)?.errorDescription
            ?? error.underlyingError?.localizedDescription
        guard let underlying = causeDesc, !underlying.isEmpty else { return }
        let causePrefix = "Cause  : "
        for wrapped in wrapText(underlying, width: innerWidth - causePrefix.count) {
            let content = "\(colors.dim)\(causePrefix)\(wrapped)\(colors.reset)"
            let rawLen = causePrefix.count + wrapped.count
            lines.append(formatBoxLine(content: content, rawLength: rawLen, innerWidth: innerWidth, borderColor: colors.border, reset: colors.reset))
        }
    }

    private static func appendActionIfPresent(
        lines: inout [String],
        error: any AppError,
        colors: BoxColors,
        innerWidth: Int
    ) {
        guard let suggestion = error.userFacingRecoverySuggestion, !suggestion.isEmpty else { return }
        lines.append("\(colors.border)│\(colors.reset)\(String(repeating: " ", count: innerWidth + 2))\(colors.border)│\(colors.reset)")
        let actionHeader = "[Action] Suggested Action:"
        let actionStyled = "\(colors.yellow)\(colors.bold)\(actionHeader)\(colors.reset)"
        lines.append(formatBoxLine(
            content: actionStyled,
            rawLength: actionHeader.count,
            innerWidth: innerWidth,
            borderColor: colors.border,
            reset: colors.reset
        ))
        for wrapped in wrapText(suggestion, width: innerWidth - 3) {
            let content = "   \(colors.cyan)\(wrapped)\(colors.reset)"
            let rawLen = 3 + wrapped.count
            lines.append(formatBoxLine(content: content, rawLength: rawLen, innerWidth: innerWidth, borderColor: colors.border, reset: colors.reset))
        }
    }

    private static func appendMetadataIfPresent(
        lines: inout [String],
        error: any AppError,
        colors: BoxColors,
        innerWidth: Int
    ) {
        guard !error.context.isEmpty else { return }
        lines.append("\(colors.border)│\(colors.reset)\(String(repeating: " ", count: innerWidth + 2))\(colors.border)│\(colors.reset)")
        let metaHeader = "Metadata:"
        let metaStyled = "\(colors.dim)\(metaHeader)\(colors.reset)"
        lines.append(formatBoxLine(
            content: metaStyled,
            rawLength: metaHeader.count,
            innerWidth: innerWidth,
            borderColor: colors.border,
            reset: colors.reset
        ))
        for (key, value) in error.context.sorted(by: { $0.key < $1.key }) {
            let pair = " • \(key): \(value)"
            for wrapped in wrapText(pair, width: innerWidth - 3) {
                let content = "  \(colors.dim)\(wrapped)\(colors.reset)"
                let rawLen = 2 + wrapped.count
                lines.append(formatBoxLine(
                    content: content,
                    rawLength: rawLen,
                    innerWidth: innerWidth,
                    borderColor: colors.border,
                    reset: colors.reset
                ))
            }
        }
    }

    private static func appendFooter(lines: inout [String], colors: BoxColors, innerWidth: Int) {
        lines.append("\(colors.border)│\(colors.reset)\(String(repeating: " ", count: innerWidth + 2))\(colors.border)│\(colors.reset)")
        let bottomBar = String(repeating: "─", count: innerWidth + 2)
        lines.append("\(colors.border)└\(bottomBar)┘\(colors.reset)")
    }

    private static func formatBoxLine(content: String, rawLength: Int, innerWidth: Int, borderColor: String, reset: String) -> String {
        let padding = max(0, innerWidth - rawLength)
        let space = String(repeating: " ", count: padding)
        return "\(borderColor)│\(reset) \(content)\(space) \(borderColor)│\(reset)"
    }

    private static func wrapLine(_ line: String, width: Int) -> [String] {
        guard line.count > width else { return [line] }
        var chunks: [String] = []
        var current = ""
        for char in line {
            current.append(char)
            if current.count >= width {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private static func wrapText(_ text: String, width: Int) -> [String] {
        guard width > 0 else { return [text] }
        let rawLines = text.components(separatedBy: "\n")
        let result = rawLines.flatMap { wrapLine($0, width: width) }
        return result.isEmpty ? [""] : result
    }

    /// 에러 발생 시 지정된 출력 형식과 채널로 포맷하여 출력하고 종료 코드를 반환합니다.
    @discardableResult
    public static func handle(
        error: any Error,
        arguments: [String] = CommandLine.arguments,
        outputDestination: CLIErrorOutputDestination = .standardError,
        exitOnCatch: Bool = true,
        exitHandler: @Sendable (Int32) -> Void = { Darwin.exit($0) }
    ) -> Int32 {
        let appError: any AppError
        if let ae = error as? any AppError {
            appError = ae
        } else {
            appError = UniversalErrorAdapter.adapt(error)
        }

        // AppErrorReporter에 자동 기록 (OTel / OSLog / 테스트 러너 디스패치)
        AppErrorReporter.shared.report(appError)

        let isJSON = arguments.contains(where: { $0 == "--json" || $0.hasPrefix("--json=") })
        let code = sysexitsCode(for: appError)

        if isJSON {
            let json = formatRFC9457JSON(for: appError, status: Int(code))
            outputDestination.write(json)
        } else {
            let useColor: Bool
            switch outputDestination {
            case .standardError:
                useColor = isTTY(fileDescriptor: STDERR_FILENO)
            case .standardOutput:
                useColor = isTTY(fileDescriptor: STDOUT_FILENO)
            case .custom:
                useColor = isTTY(fileDescriptor: STDERR_FILENO)
            }
            let diagnosticBox = formatDiagnosticBox(for: appError, useColor: useColor)
            outputDestination.write(diagnosticBox)
        }

        if exitOnCatch {
            exitHandler(code)
        }
        return code
    }
}

// MARK: - Global Interceptor Function `runWithUniversalError`

/// CLI 메인 실행부에서 에러를 전역적으로 가로채어 RFC 9457 JSON 또는 ANSI 진단 박스로 포맷하고
/// POSIX Sysexits 코드로 안전하게 종료하는 전역 인터셉터 (동기 클로저 버전).
@discardableResult
public func runWithUniversalError(
    arguments: [String] = CommandLine.arguments,
    exitOnCatch: Bool = true,
    outputDestination: CLIErrorOutputDestination = .standardError,
    exitHandler: @Sendable @escaping (Int32) -> Void = { Darwin.exit($0) },
    _ operation: () throws -> Void
) -> Int32 {
    do {
        try operation()
        return POSIXSysexits.ok
    } catch {
        return UniversalCLIErrorHandler.handle(
            error: error,
            arguments: arguments,
            outputDestination: outputDestination,
            exitOnCatch: exitOnCatch,
            exitHandler: exitHandler
        )
    }
}

/// CLI 메인 실행부에서 에러를 전역적으로 가로채어 RFC 9457 JSON 또는 ANSI 진단 박스로 포맷하고
/// POSIX Sysexits 코드로 안전하게 종료하는 전역 인터셉터 (비동기 클로저 버전).
@discardableResult
public func runWithUniversalError(
    arguments: [String] = CommandLine.arguments,
    exitOnCatch: Bool = true,
    outputDestination: CLIErrorOutputDestination = .standardError,
    exitHandler: @Sendable @escaping (Int32) -> Void = { Darwin.exit($0) },
    _ operation: () async throws -> Void
) async -> Int32 {
    do {
        try await operation()
        return POSIXSysexits.ok
    } catch {
        return UniversalCLIErrorHandler.handle(
            error: error,
            arguments: arguments,
            outputDestination: outputDestination,
            exitOnCatch: exitOnCatch,
            exitHandler: exitHandler
        )
    }
}

// MARK: - AgentCLICommand Extension

extension AgentCLICommand {
    /// `AgentCLICommand`를 실행하면서 발생하는 오류를 Universal CLI Error 체계로 가로챕니다.
    public func handleWithUniversalError(
        _ args: [String],
        exitOnCatch: Bool = true,
        outputDestination: CLIErrorOutputDestination = .standardError
    ) async -> AgentCLIExit {
        let code = await runWithUniversalError(
            arguments: args,
            exitOnCatch: exitOnCatch,
            outputDestination: outputDestination
        ) {
            let result = await self.handle(args)
            if case let .handled(exitCode) = result, exitCode != 0 {
                // 비정상 종료 코드 처리
            }
        }
        return .handled(code)
    }
}
