import Foundation

public enum ContractSurface: String, Sendable, CaseIterable, Codable, Hashable {
    case gui
    case cli
    case core
    case stateMirror
}

public typealias SurfaceKind = ContractSurface

public struct SurfaceCoverage: Sendable, Equatable, Hashable {
    public let supportedSurfaces: Set<ContractSurface>

    public init(supportedSurfaces: Set<ContractSurface>) {
        self.supportedSurfaces = supportedSurfaces
    }

    public var isComplete: Bool {
        supportedSurfaces.count == ContractSurface.allCases.count
    }

    public var missingSurfaces: Set<ContractSurface> {
        Set(ContractSurface.allCases).subtracting(supportedSurfaces)
    }

    public static let full = SurfaceCoverage(supportedSurfaces: Set(ContractSurface.allCases))
    public static let none = SurfaceCoverage(supportedSurfaces: [])
}

public protocol ActionIntent: Sendable, Hashable, CaseIterable {
    var intentIdentifier: String { get }
    var cliCommandName: String { get }
    var guiActionName: String { get }
    var affectsStateMirror: Bool { get }
}

public extension ActionIntent {
    var intentIdentifier: String {
        String(describing: self)
    }

    var cliCommandName: String {
        String(describing: self)
    }

    var guiActionName: String {
        String(describing: self)
    }

    var affectsStateMirror: Bool {
        true
    }
}

public extension ActionIntent where Self: RawRepresentable, Self.RawValue == String {
    var intentIdentifier: String {
        rawValue
    }

    var cliCommandName: String {
        rawValue
    }

    var guiActionName: String {
        rawValue
    }
}

public struct IntentContractSpec<Intent: ActionIntent>: Sendable, Equatable {
    public let intent: Intent
    public let requiredSurfaces: Set<ContractSurface>
    public let affectsStateMirror: Bool
    public let cliSubcommands: [String]
    public let guiTriggerIdentifier: String

    public init(
        intent: Intent,
        requiredSurfaces: Set<ContractSurface> = Set(ContractSurface.allCases),
        affectsStateMirror: Bool = true,
        cliSubcommands: [String] = [],
        guiTriggerIdentifier: String = ""
    ) {
        self.intent = intent
        self.requiredSurfaces = requiredSurfaces
        self.affectsStateMirror = affectsStateMirror
        self.cliSubcommands = cliSubcommands.isEmpty ? [intent.cliCommandName] : cliSubcommands
        self.guiTriggerIdentifier = guiTriggerIdentifier.isEmpty ? intent.guiActionName : guiTriggerIdentifier
    }
}

public struct ContractViolation: Sendable, Equatable, Hashable {
    public let appSlug: String
    public let intentIdentifier: String?
    public let surface: ContractSurface?
    public let message: String

    public init(
        appSlug: String,
        intentIdentifier: String? = nil,
        surface: ContractSurface? = nil,
        message: String
    ) {
        self.appSlug = appSlug
        self.intentIdentifier = intentIdentifier
        self.surface = surface
        self.message = message
    }
}

public struct ContractValidationReport<Intent: ActionIntent>: Sendable {
    public let appSlug: String
    public let isValid: Bool
    public let totalIntents: Int
    public let surfaceGaps: [Intent: Set<ContractSurface>]
    public let violations: [ContractViolation]

    public init(
        appSlug: String,
        isValid: Bool,
        totalIntents: Int,
        surfaceGaps: [Intent: Set<ContractSurface>],
        violations: [ContractViolation]
    ) {
        self.appSlug = appSlug
        self.isValid = isValid
        self.totalIntents = totalIntents
        self.surfaceGaps = surfaceGaps
        self.violations = violations
    }
}

public protocol DeclarativeAppContract: Sendable {
    associatedtype Intent: ActionIntent

    var appSlug: String { get }
    var executableName: String { get }
    var bundleIdentifier: String { get }
    var supportedIntents: [Intent] { get }

    var hasDurableStorage: Bool { get }
    var hasStateMirror: Bool { get }
    var hasCLICapabilities: Bool { get }

    func coverage(for intent: Intent) -> SurfaceCoverage
    func validateContract() -> ContractValidationReport<Intent>
}

public extension DeclarativeAppContract {
    var executableName: String {
        appSlug
    }

    var bundleIdentifier: String {
        "net.ranode.\(appSlug)"
    }

    var hasDurableStorage: Bool {
        true
    }

    var hasStateMirror: Bool {
        true
    }

    var hasCLICapabilities: Bool {
        true
    }

    func coverage(for intent: Intent) -> SurfaceCoverage {
        .full
    }

    private func validateGlobalRequirements() -> [ContractViolation] {
        let checks: [(Bool, ContractSurface?, String)] = [
            (supportedIntents.isEmpty, nil, "App contract declares no supported intents"),
            (!hasCLICapabilities, .cli, "App contract requires CLI surface support"),
            (!hasStateMirror, .stateMirror, "App contract requires StateMirror surface support")
        ]
        return checks.compactMap { failed, surface, message in
            guard failed else { return nil }
            return ContractViolation(appSlug: appSlug, surface: surface, message: message)
        }
    }

    private func validateIntentCoverage() -> ([Intent: Set<ContractSurface>], [ContractViolation]) {
        var gaps: [Intent: Set<ContractSurface>] = [:]
        var violations: [ContractViolation] = []
        for intent in supportedIntents {
            let cov = coverage(for: intent)
            guard !cov.isComplete else { continue }
            gaps[intent] = cov.missingSurfaces
            for missing in cov.missingSurfaces.sorted(by: { $0.rawValue < $1.rawValue }) {
                violations.append(
                    ContractViolation(
                        appSlug: appSlug,
                        intentIdentifier: intent.intentIdentifier,
                        surface: missing,
                        message: "Intent '\(intent.intentIdentifier)' lacks coverage on surface '\(missing.rawValue)'"
                    )
                )
            }
        }
        return (gaps, violations)
    }

    func validateContract() -> ContractValidationReport<Intent> {
        let globalViolations = validateGlobalRequirements()
        let (gaps, intentViolations) = validateIntentCoverage()
        let violations = globalViolations + intentViolations
        return ContractValidationReport(
            appSlug: appSlug,
            isValid: violations.isEmpty,
            totalIntents: supportedIntents.count,
            surfaceGaps: gaps,
            violations: violations
        )
    }
}

public struct AnyDeclarativeAppContract<Intent: ActionIntent>: DeclarativeAppContract {
    public let appSlug: String
    public let executableName: String
    public let bundleIdentifier: String
    public let supportedIntents: [Intent]
    public let hasDurableStorage: Bool
    public let hasStateMirror: Bool
    public let hasCLICapabilities: Bool
    private let coverageProvider: @Sendable (Intent) -> SurfaceCoverage

    public init(
        appSlug: String,
        executableName: String? = nil,
        bundleIdentifier: String? = nil,
        supportedIntents: [Intent],
        hasDurableStorage: Bool = true,
        hasStateMirror: Bool = true,
        hasCLICapabilities: Bool = true,
        coverageProvider: (@Sendable (Intent) -> SurfaceCoverage)? = nil
    ) {
        self.appSlug = appSlug
        self.executableName = executableName ?? appSlug
        self.bundleIdentifier = bundleIdentifier ?? "net.ranode.\(appSlug)"
        self.supportedIntents = supportedIntents
        self.hasDurableStorage = hasDurableStorage
        self.hasStateMirror = hasStateMirror
        self.hasCLICapabilities = hasCLICapabilities
        self.coverageProvider = coverageProvider ?? { _ in .full }
    }

    public func coverage(for intent: Intent) -> SurfaceCoverage {
        coverageProvider(intent)
    }
}
