import Foundation


/// Helper to extract string identifiers from enum cases.
private func identifierForCase<T>(_ value: T) -> String {
    if let raw = (value as? any RawRepresentable)?.rawValue as? String {
        return raw
    }
    if let identifiable = value as? any Identifiable, let idString = identifiable.id as? String {
        return idString
    }
    return String(describing: value)
}

public enum RouteParityGate {
    /// Pluggable reporter for test assertion failures (e.g. XCTFail).
    public nonisolated(unsafe) static var failureReporter: ((String, StaticString, UInt) -> Void)?

    /// Converts camelCase, PascalCase, or snake_case strings into normalized kebab-case.
    /// Example: 'userProfile' -> 'user-profile', 'user_profile' -> 'user-profile'
    public static func canonicalToken(_ input: String) -> String {
        var result = ""
        var prevIsUppercase = false
        var prevIsHyphen = false

        for char in input {
            if char == "_" || char == "-" {
                if !result.isEmpty && !prevIsHyphen {
                    result.append("-")
                    prevIsHyphen = true
                }
                prevIsUppercase = false
            } else if char.isUppercase {
                if !result.isEmpty && !prevIsHyphen && !prevIsUppercase {
                    result.append("-")
                }
                result.append(char.lowercased())
                prevIsUppercase = true
                prevIsHyphen = false
            } else {
                result.append(char)
                prevIsUppercase = false
                prevIsHyphen = false
            }
        }
        return result
    }

    /// Computes the parity differences between route identifiers and command identifiers.
    public static func computeParityDiff(
        routes: [String],
        commands: [String]
    ) -> [ParityDiff] {
        // Map canonical token to original representation for clear error reporting
        var routeMap: [String: String] = [:]
        for route in routes {
            let canonical = canonicalToken(route)
            routeMap[canonical] = route
        }

        var commandMap: [String: String] = [:]
        for command in commands {
            let canonical = canonicalToken(command)
            commandMap[canonical] = command
        }

        let routeCanonicalSet = Set(routeMap.keys)
        let commandCanonicalSet = Set(commandMap.keys)

        var differences: [ParityDiff] = []

        // Routes in UI missing from CLI commands (missing in CLI)
        for missingCLI in routeCanonicalSet.subtracting(commandCanonicalSet).sorted() {
            let originalRoute = routeMap[missingCLI] ?? missingCLI
            differences.append(
                ParityDiff(
                    path: originalRoute,
                    kind: .missingKeyInCLI,
                    cliValue: nil,
                    guiValue: originalRoute,
                    message: "UI route '\(originalRoute)' is missing in CLI commands"
                )
            )
        }

        // Commands in CLI missing from UI routes (missing in GUI)
        for missingUI in commandCanonicalSet.subtracting(routeCanonicalSet).sorted() {
            let originalCommand = commandMap[missingUI] ?? missingUI
            differences.append(
                ParityDiff(
                    path: originalCommand,
                    kind: .missingKeyInGUI,
                    cliValue: originalCommand,
                    guiValue: nil,
                    message: "CLI command '\(originalCommand)' is missing in UI routes"
                )
            )
        }

        return differences
    }

    /// Verifies parity between Route cases and Command cases, returning a ParityVerdict.
    public static func verifyParity<Route: CaseIterable, Command: CaseIterable>(
        routes: Route.Type,
        commands: Command.Type
    ) -> ParityVerdict {
        let routeIdentifiers = Route.allCases.map { identifierForCase($0) }
        let commandIdentifiers = Command.allCases.map { identifierForCase($0) }

        let diffs = computeParityDiff(routes: routeIdentifiers, commands: commandIdentifiers)
        let allCanonicalKeys = Set(routeIdentifiers.map { canonicalToken($0) })
            .union(Set(commandIdentifiers.map { canonicalToken($0) }))
        let totalChecked = allCanonicalKeys.count

        return ParityVerdict(
            isIsomorphic: diffs.isEmpty,
            differences: diffs,
            comparedNodesCount: totalChecked
        )
    }

    /// Format a friendly error message detailing any UI/CLI parity discrepancies.
    public static func formatFailureMessage(
        verdict: ParityVerdict,
        routeTypeName: String,
        commandTypeName: String
    ) -> String {
        let missingCLI = verdict.differences.filter { $0.kind == .missingKeyInCLI }.compactMap { $0.guiValue ?? $0.path }
        let missingUI = verdict.differences.filter { $0.kind == .missingKeyInGUI }.compactMap { $0.cliValue ?? $0.path }

        var lines: [String] = []
        lines.append("❌ Surface Parity Violation between UI '\(routeTypeName)' and CLI '\(commandTypeName)':")

        if !missingCLI.isEmpty {
            lines.append("  Missing CLI commands for UI routes (\(missingCLI.count)):")
            for item in missingCLI {
                lines.append("    - \(item)")
            }
        }

        if !missingUI.isEmpty {
            lines.append("  Missing UI routes for CLI commands (\(missingUI.count)):")
            for item in missingUI {
                lines.append("    - \(item)")
            }
        }

        lines.append("Ensure every UI route has a corresponding CLI command and vice versa for 1:1 parity.")
        return lines.joined(separator: "\n")
    }
}

/// Convenience alias for RouteParityGate.
public typealias ParityAssertion = RouteParityGate

/// Asserts 1:1 Surface Parity between UI Route cases and CLI Command cases in XCTest suites.
///
/// Can be invoked with:
/// ```swift
/// assertSurfaceParity(routes: AppRoute.self, commands: AppCLICommand.self)
/// ```
@discardableResult
public func assertSurfaceParity<Route: CaseIterable, Command: CaseIterable>(
    routes: Route.Type,
    commands: Command.Type,
    file: StaticString = #file,
    line: UInt = #line
) -> Bool {
    let verdict = RouteParityGate.verifyParity(routes: routes, commands: commands)

    if !verdict.isIsomorphic {
        let message = RouteParityGate.formatFailureMessage(
            verdict: verdict,
            routeTypeName: String(describing: routes),
            commandTypeName: String(describing: commands)
        )
        if let reporter = RouteParityGate.failureReporter {
            reporter(message, file, line)
        } else {
            fputs("\(message)\n", stderr)
        }
        return false
    }

    return true
}
