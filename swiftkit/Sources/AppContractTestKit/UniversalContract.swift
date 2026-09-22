import Foundation

public struct ContractID: Hashable, Equatable, Sendable, Codable, CustomStringConvertible, RawRepresentable, CaseIterable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }

    public static let cliHelpParityV1 = ContractID("7f8b9c0d-cli-help-v1")
    public static let stateMirrorSafetyV1 = ContractID("3a4b5c6d-state-mirror-v1")
    public static let codableIsomorphismV1 = ContractID("f1e2d3c4-codable-iso-v1")
    public static let hermeticSandboxV1 = ContractID("9c1d2e3f-hermetic-sandbox-v1")

    public static let allCases: [ContractID] = [
        .cliHelpParityV1,
        .stateMirrorSafetyV1,
        .codableIsomorphismV1,
        .hermeticSandboxV1
    ]
}

public protocol UniversalContractTarget: Sendable {
    var name: String { get }
    var cliBinaryName: String { get }
    var statePath: String { get }
    var modelType: String { get }
    var cliHelpOutput: String? { get }
    var cliCommands: [String] { get }
    var samplePayload: Data? { get }
    var stateData: Data? { get }
    var allowedSandboxDirectories: [String] { get }
    var accessPaths: [String] { get }
}

public extension UniversalContractTarget {
    var modelType: String {
        "DefaultModel"
    }

    var cliHelpOutput: String? {
        nil
    }

    var cliCommands: [String] {
        []
    }

    var samplePayload: Data? {
        nil
    }

    var stateData: Data? {
        nil
    }

    var allowedSandboxDirectories: [String] {
        []
    }

    var accessPaths: [String] {
        []
    }
}

public struct UniversalContractTargetDescriptor: UniversalContractTarget, Sendable, Equatable {
    public let name: String
    public let cliBinaryName: String
    public let statePath: String
    public let modelType: String
    public let cliHelpOutput: String?
    public let cliCommands: [String]
    public let samplePayload: Data?
    public let stateData: Data?
    public let allowedSandboxDirectories: [String]
    public let accessPaths: [String]

    public init(
        name: String,
        cliBinaryName: String,
        statePath: String,
        modelType: String = "DefaultModel",
        cliHelpOutput: String? = nil,
        cliCommands: [String] = [],
        samplePayload: Data? = nil,
        stateData: Data? = nil,
        allowedSandboxDirectories: [String] = [],
        accessPaths: [String] = []
    ) {
        self.name = name
        self.cliBinaryName = cliBinaryName
        self.statePath = statePath
        self.modelType = modelType
        self.cliHelpOutput = cliHelpOutput
        self.cliCommands = cliCommands
        self.samplePayload = samplePayload
        self.stateData = stateData
        self.allowedSandboxDirectories = allowedSandboxDirectories
        self.accessPaths = accessPaths
    }
}

public struct ContractAssertionResult: Sendable, Equatable {
    public let isPassed: Bool
    public let message: String
    public let counterExample: String?

    public init(isPassed: Bool, message: String, counterExample: String? = nil) {
        self.isPassed = isPassed
        self.message = message
        self.counterExample = counterExample
    }

    public static func pass(message: String = "Contract invariant satisfied") -> ContractAssertionResult {
        ContractAssertionResult(isPassed: true, message: message, counterExample: nil)
    }

    public static func fail(message: String, counterExample: String? = nil) -> ContractAssertionResult {
        ContractAssertionResult(isPassed: false, message: message, counterExample: counterExample)
    }
}

public typealias ContractAssertion = @Sendable (any UniversalContractTarget) throws -> ContractAssertionResult

import os

public final class UniversalContractRegistry: Sendable {
    private let storage: OSAllocatedUnfairLock<[ContractID: ContractAssertion]>

    public static let standard: UniversalContractRegistry = {
        let registry = UniversalContractRegistry()
        registry.registerStandardAssertions()
        return registry
    }()

    public init() {
        self.storage = OSAllocatedUnfairLock(initialState: [:])
    }

    public func register(contractID: ContractID, assertion: @escaping ContractAssertion) {
        storage.withLock { assertions in
            assertions[contractID] = assertion
        }
    }

    public func unregister(contractID: ContractID) {
        storage.withLock { assertions in
            assertions.removeValue(forKey: contractID)
        }
    }

    public func assertion(for contractID: ContractID) -> ContractAssertion? {
        storage.withLock { assertions in
            assertions[contractID]
        }
    }

    public func hasContract(_ contractID: ContractID) -> Bool {
        storage.withLock { assertions in
            assertions[contractID] != nil
        }
    }

    public var registeredContractIDs: [ContractID] {
        storage.withLock { assertions in
            Array(assertions.keys)
        }
    }

    private static func hasPathTraversal(_ path: String) -> Bool {
        let traversals = ["../", "..\\"]
        if traversals.contains(where: { path.contains($0) }) {
            return true
        }
        return path.hasSuffix("/..") || path == ".."
    }

    public func registerStandardAssertions() {
        registerCliHelpAssertion()
        registerStateMirrorSafetyAssertion()
        registerCodableIsomorphismAssertion()
        registerHermeticSandboxAssertion()
    }

    private func registerCliHelpAssertion() {
        register(contractID: .cliHelpParityV1) { target in
            let binaryName = target.cliBinaryName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !binaryName.isEmpty else {
                return .fail(
                    message: "Target cliBinaryName must not be empty",
                    counterExample: "cliBinaryName is empty string"
                )
            }
            guard let helpOutput = target.cliHelpOutput, !helpOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .fail(
                    message: "Target cliHelpOutput is missing or empty",
                    counterExample: "cliHelpOutput is nil or empty"
                )
            }
            let validIndicators = [binaryName, "help", "usage"]
            let containsIndicator = validIndicators.contains { helpOutput.localizedCaseInsensitiveContains($0) }
            guard containsIndicator else {
                return .fail(
                    message: "CLI help output missing binary name or usage indicators",
                    counterExample: "cliHelpOutput does not contain '\(binaryName)', 'usage', or 'help': '\(helpOutput)'"
                )
            }
            for command in target.cliCommands {
                if !helpOutput.contains(command) {
                    return .fail(
                        message: "CLI help output lacks parity for subcommand '\(command)'",
                        counterExample: "Subcommand '\(command)' not found in CLI help output"
                    )
                }
            }
            return .pass(message: "CLI help parity verified for binary '\(binaryName)'")
        }
    }

    private func registerStateMirrorSafetyAssertion() {
        register(contractID: .stateMirrorSafetyV1) { target in
            let path = target.statePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else {
                return .fail(
                    message: "Target statePath must not be empty",
                    counterExample: "statePath is empty"
                )
            }
            if Self.hasPathTraversal(path) {
                return .fail(
                    message: "statePath violates directory containment constraints",
                    counterExample: "Path traversal sequence detected in '\(path)'"
                )
            }
            if let stateData = target.stateData {
                do {
                    let parsed = try JSONSerialization.jsonObject(with: stateData, options: [])
                    guard parsed is [String: Any] else {
                        return .fail(
                            message: "stateData must be a structured JSON object dictionary",
                            counterExample: "Parsed JSON root is \(type(of: parsed)) instead of dictionary"
                        )
                    }
                } catch {
                    return .fail(
                        message: "stateData is corrupted or invalid JSON",
                        counterExample: "JSON parsing failed with error: \(error.localizedDescription)"
                    )
                }
            }
            return .pass(message: "State mirror safety verified for path '\(path)'")
        }
    }

    private func registerCodableIsomorphismAssertion() {
        register(contractID: .codableIsomorphismV1) { target in
            guard let payload = target.samplePayload, !payload.isEmpty else {
                return .fail(
                    message: "samplePayload must be provided for codable isomorphism check",
                    counterExample: "samplePayload is nil or empty"
                )
            }
            let initialObject: Any
            do {
                initialObject = try JSONSerialization.jsonObject(with: payload, options: [])
            } catch {
                return .fail(
                    message: "samplePayload is not valid JSON",
                    counterExample: "Failed to parse initial payload: \(error.localizedDescription)"
                )
            }
            guard JSONSerialization.isValidJSONObject(initialObject) else {
                return .fail(
                    message: "samplePayload root is not a valid JSON object",
                    counterExample: "Invalid JSON object structure: \(type(of: initialObject))"
                )
            }
            let reEncodedData: Data
            do {
                reEncodedData = try JSONSerialization.data(withJSONObject: initialObject, options: [.sortedKeys])
            } catch {
                return .fail(
                    message: "Failed to re-encode JSON object",
                    counterExample: "Serialization error: \(error.localizedDescription)"
                )
            }
            let roundTripObject: Any
            do {
                roundTripObject = try JSONSerialization.jsonObject(with: reEncodedData, options: [])
            } catch {
                return .fail(
                    message: "Failed to decode re-encoded JSON payload",
                    counterExample: "Round-trip parse error: \(error.localizedDescription)"
                )
            }
            return Self.compareJsonPayload(
                initialObject: initialObject,
                roundTripObject: roundTripObject,
                modelType: target.modelType
            )
        }
    }

    private static func compareJsonPayload(
        initialObject: Any,
        roundTripObject: Any,
        modelType: String
    ) -> ContractAssertionResult {
        if let dict1 = initialObject as? NSDictionary, let dict2 = roundTripObject as? NSDictionary {
            guard dict1.isEqual(to: dict2) else {
                return .fail(
                    message: "JSON object round-trip dictionary mismatch",
                    counterExample: "Mismatch between original payload dictionary and round-trip dictionary"
                )
            }
            return .pass(message: "Codable isomorphism verified for model type '\(modelType)'")
        }
        if let arr1 = initialObject as? NSArray, let arr2 = roundTripObject as? NSArray {
            guard arr1.isEqual(to: arr2) else {
                return .fail(
                    message: "JSON object round-trip array mismatch",
                    counterExample: "Mismatch between original payload array and round-trip array"
                )
            }
            return .pass(message: "Codable isomorphism verified for model type '\(modelType)'")
        }
        return .fail(
            message: "Unsupported JSON root type for isomorphism comparison",
            counterExample: "Root type: \(type(of: initialObject))"
        )
    }

    private func registerHermeticSandboxAssertion() {
        register(contractID: .hermeticSandboxV1) { target in
            guard !target.accessPaths.isEmpty else {
                return .pass(message: "Hermetic sandbox verified with zero accessed paths")
            }
            guard !target.allowedSandboxDirectories.isEmpty else {
                return .fail(
                    message: "Hermetic sandbox has no allowed directories but access paths were declared",
                    counterExample: "allowedSandboxDirectories is empty while accessPaths has \(target.accessPaths.count) items"
                )
            }
            for accessPath in target.accessPaths {
                if let failure = Self.validateSandboxPath(accessPath, allowedDirectories: target.allowedSandboxDirectories) {
                    return failure
                }
            }
            return .pass(message: "Hermetic sandbox verified for \(target.accessPaths.count) accessed paths")
        }
    }

    private static func validateSandboxPath(
        _ path: String,
        allowedDirectories: [String]
    ) -> ContractAssertionResult? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasPathTraversal(trimmed) {
            return .fail(
                message: "Access path contains path traversal sequence",
                counterExample: "Path traversal detected in access path '\(trimmed)'"
            )
        }
        let standardized = (trimmed as NSString).standardizingPath
        let isContained = allowedDirectories.contains { allowedDir in
            let stdAllowed = (allowedDir as NSString).standardizingPath
            let prefix = stdAllowed.hasSuffix("/") ? stdAllowed : stdAllowed + "/"
            return standardized == stdAllowed || standardized.hasPrefix(prefix)
        }
        guard isContained else {
            return .fail(
                message: "Path escapes sandbox boundaries",
                counterExample: "Path '\(standardized)' is outside allowed directories: \(allowedDirectories)"
            )
        }
        return nil
    }
}
