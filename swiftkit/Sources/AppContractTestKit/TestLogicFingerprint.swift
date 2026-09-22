import Foundation

public extension ContractID {
    static let codableRoundTrip = ContractID.codableIsomorphismV1
    static let cliHelpExitZero = ContractID.cliHelpParityV1
    static let stateMirrorEmit = ContractID.stateMirrorSafetyV1
    static let hermeticSandbox = ContractID.hermeticSandboxV1
}

public enum TestPatternFingerprint: String, Sendable, CaseIterable, Codable, Hashable {
    case codableRoundTrip
    case cliHelpExitZero
    case stateMirrorEmit
    case hermeticSandbox
    case unknownCustomDomain

    public var contractID: ContractID? {
        switch self {
        case .codableRoundTrip:
            return .codableRoundTrip
        case .cliHelpExitZero:
            return .cliHelpExitZero
        case .stateMirrorEmit:
            return .stateMirrorEmit
        case .hermeticSandbox:
            return .hermeticSandbox
        case .unknownCustomDomain:
            return nil
        }
    }
}

public struct TestLogicAnalyzer: Sendable {
    public init() {}

    public func analyze(_ source: String) -> TestPatternFingerprint {
        Self.analyze(source)
    }

    public func fingerprint(of source: String) -> TestPatternFingerprint {
        Self.analyze(source)
    }

    public func contractID(for source: String) -> ContractID? {
        Self.contractID(for: source)
    }

    public func detectContractID(_ source: String) -> ContractID? {
        Self.contractID(for: source)
    }

    public static func contractID(for source: String) -> ContractID? {
        analyze(source).contractID
    }

    public static func fingerprint(of source: String) -> TestPatternFingerprint {
        analyze(source)
    }

    public static func detectContractID(_ source: String) -> ContractID? {
        analyze(source).contractID
    }

    public static func analyze(_ source: String) -> TestPatternFingerprint {
        let cleaned = stripComments(from: source)

        let matchers: [(matcher: (String) -> Bool, pattern: TestPatternFingerprint)] = [
            (StateMirrorMatcher.matches, .stateMirrorEmit),
            (CLIHelpMatcher.matches, .cliHelpExitZero),
            (CodableMatcher.matches, .codableRoundTrip),
            (HermeticSandboxMatcher.matches, .hermeticSandbox)
        ]

        for item in matchers {
            if item.matcher(cleaned) {
                return item.pattern
            }
        }

        return .unknownCustomDomain
    }

    private static func stripComments(from source: String) -> String {
        var result = ""
        var index = source.startIndex
        let end = source.endIndex

        while index < end {
            guard source[index] == "/" else {
                result.append(source[index])
                index = source.index(after: index)
                continue
            }
            let nextIndex = source.index(after: index)
            guard nextIndex < end else {
                result.append(source[index])
                break
            }
            if source[nextIndex] == "/" {
                index = skipLineComment(in: source, from: nextIndex, end: end)
            } else if source[nextIndex] == "*" {
                index = skipBlockComment(in: source, from: nextIndex, end: end)
            } else {
                result.append(source[index])
                index = nextIndex
            }
        }
        return result
    }

    private static func skipLineComment(in source: String, from start: String.Index, end: String.Index) -> String.Index {
        var scan = start
        while scan < end && source[scan] != "\n" {
            scan = source.index(after: scan)
        }
        return scan
    }

    private static func skipBlockComment(in source: String, from start: String.Index, end: String.Index) -> String.Index {
        var scan = start
        while scan < end {
            let next = source.index(after: scan)
            if source[scan] == "*" && next < end && source[next] == "/" {
                return source.index(after: next)
            }
            scan = next
        }
        return end
    }
}

private enum SourceMatchers {
    static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

private enum StateMirrorMatcher {
    static func matches(_ source: String) -> Bool {
        let mirrorPublishKeywords = ["StateMirror", "LifecycleStateMirror", "StatePublisher"]
        let hasMirrorKeyword = SourceMatchers.containsAny(source, mirrorPublishKeywords)
        let hasStateMirrorPublish = source.contains(".publish(") && hasMirrorKeyword
        if hasStateMirrorPublish {
            return true
        }

        let jsonOperations = ["appendingPathComponent", "Data(contentsOf:", "fileExists"]
        let hasJsonFile = source.contains(".json") && SourceMatchers.containsAny(source, jsonOperations)
        let hasPayloadVerification = source.contains("[\"state\"]") || source.contains("[\"app\"]")
        let hasContentEvidence = hasJsonFile || hasPayloadVerification

        let hasStateDirEnv = source.contains("SWIFT_APP_STATE_DIRECTORY")
        let matchesEnvState = hasStateDirEnv && hasContentEvidence

        let mirrorKeywords = ["StateMirror", "stateDir", "mirror"]
        let hasMirrorInFile = SourceMatchers.containsAny(source, mirrorKeywords)
        let matchesFileState = hasJsonFile && hasPayloadVerification && hasMirrorInFile

        return matchesEnvState || matchesFileState
    }
}

private enum CLIHelpMatcher {
    static func matches(_ source: String) -> Bool {
        let helpKeywords = ["\"--help\"", "\"-h\""]
        let hasHelpArgument = SourceMatchers.containsAny(source, helpKeywords)

        let usageKeywords = ["usageText", "usage"]
        let hasUsageAssertion = SourceMatchers.containsAny(source, usageKeywords)

        let runnerKeywords = [
            "CLI.run", "AdoptCLI", "AuditCLI",
            "ProcessRunner", "Command.run", ".run("
        ]
        let hasCLIRunner = SourceMatchers.containsAny(source, runnerKeywords)

        let exitCodeKeywords = [
            "success", "rawValue", "exitCode == 0",
            "exitCode, 0", "== 0", ", 0)", ", 0,"
        ]
        let hasExitCodeZero = SourceMatchers.containsAny(source, exitCodeKeywords)

        let executionSignals = [hasCLIRunner, hasExitCodeZero, hasUsageAssertion]
        let hasExecutionResult = executionSignals.contains(true)

        if hasHelpArgument && hasExecutionResult {
            return true
        }

        return hasUsageAssertion && hasCLIRunner && source.contains("isEmpty")
    }
}

private enum CodableMatcher {
    static func matches(_ source: String) -> Bool {
        let hasJsonPair = source.contains("JSONEncoder") && source.contains("JSONDecoder")
        let hasPlistPair = source.contains("PropertyListEncoder") && source.contains("PropertyListDecoder")
        let hasGenericPair = source.contains(".encode(") && source.contains(".decode(")

        let pairs = [hasJsonPair, hasPlistPair, hasGenericPair]
        return pairs.contains(true)
    }
}

private enum HermeticSandboxMatcher {
    static func matches(_ source: String) -> Bool {
        let tempKeywords = ["temporaryDirectory", "NSTemporaryDirectory()"]
        let hasTempDir = SourceMatchers.containsAny(source, tempKeywords)

        let uuidKeywords = ["UUID().uuidString", "UUID()"]
        let hasUUIDPath = SourceMatchers.containsAny(source, uuidKeywords)

        let cleanupKeywords = ["removeItem", "tearDown"]
        let hasCleanup = SourceMatchers.containsAny(source, cleanupKeywords)

        let setenvKeywords = ["setenv(", "unsetenv("]
        let envTargetKeywords = ["HOME", "DIRECTORY", "ROOT"]
        let hasSetenv = SourceMatchers.containsAny(source, setenvKeywords)
        let hasEnvTarget = SourceMatchers.containsAny(source, envTargetKeywords)
        let hasEnvIsolation = hasSetenv && hasEnvTarget

        let hasExplicitTenantKeyword = source.contains("tenant:") && source.contains("tenantID")
        let hasTenantIsolation = source.contains("TenantIsolation") || hasExplicitTenantKeyword

        let isolationSignals = [hasUUIDPath, hasCleanup, hasEnvIsolation]
        let hasIsolationEvidence = isolationSignals.contains(true)

        if hasTempDir && hasIsolationEvidence {
            return true
        }

        let hasLocalDirectoryEvidence = hasTempDir || hasCleanup
        let hasIsolationMatch = hasTenantIsolation || hasEnvIsolation
        return hasLocalDirectoryEvidence && hasIsolationMatch
    }
}
