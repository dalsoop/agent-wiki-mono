import Foundation

public struct CredentialField: Sendable, Equatable {
    public let key: String
    public let label: String
    public let secret: Bool
    public let placeholder: String?
    public init(key: String, label: String, secret: Bool = false, placeholder: String? = nil) {
        self.key = key; self.label = label; self.secret = secret; self.placeholder = placeholder
    }
}

public struct CredentialStep: Sendable, Equatable {
    public let text: String
    public let url: String?
    public let button: String?
    public init(text: String, url: String? = nil, button: String? = nil) {
        self.text = text; self.url = url; self.button = button
    }
}

public struct CredentialVerify: Sendable, Equatable {
    public let command: String
    public let args: [String]
    public let successContains: String?
    public init(command: String, args: [String], successContains: String? = nil) {
        self.command = command; self.args = args; self.successContains = successContains
    }
}

public enum CredentialStorage: String, Sendable, Equatable { case keychain, memory }

public struct CredentialSpec: Sendable, Equatable {
    public let profile: String; public let title: String; public let reason: String
    public let steps: [CredentialStep]; public let fields: [CredentialField]
    public let storage: CredentialStorage; public let verify: CredentialVerify?; public let meta: [String: String]
    public init(profile: String, title: String, reason: String = "", steps: [CredentialStep] = [], fields: [CredentialField], storage: CredentialStorage = .keychain, verify: CredentialVerify? = nil, meta: [String: String] = [:]) {
        self.profile = profile; self.title = title; self.reason = reason; self.steps = steps; self.fields = fields
        self.storage = storage; self.verify = verify; self.meta = meta
    }
}

public enum CredentialPromptOutcome: Sendable, Equatable { case saved([String: String]), cancelled, unavailable }

public struct StoredCredential: Sendable, Codable, Equatable {
    public var fields: [String: String]; public var fieldOrder: [String]; public var secretKeys: [String]; public var meta: [String: String]
    public init(fields: [String: String], fieldOrder: [String], secretKeys: [String], meta: [String: String]) {
        self.fields = fields; self.fieldOrder = fieldOrder; self.secretKeys = secretKeys; self.meta = meta
    }
}

public struct CredentialInfo: Sendable, Equatable, Codable {
    public let profile: String; public let fields: [String]; public let source: String?
    public init(profile: String, fields: [String], source: String?) { self.profile = profile; self.fields = fields; self.source = source }
}

public struct CredentialRequestResult: Sendable, Equatable {
    public let info: CredentialInfo; public let stored: Bool; public let verified: Bool?; public let message: String
    public init(info: CredentialInfo, stored: Bool, verified: Bool?, message: String) { self.info = info; self.stored = stored; self.verified = verified; self.message = message }
}

public enum CredentialError: Error, Equatable, Sendable, CustomStringConvertible {
    case declined, promptUnavailable, unknownProfile(String), missingField(String), keychain(Int32), executableNotFound(String)
    public var description: String {
        switch self {
        case .declined: "user declined the credential request"
        case .promptUnavailable: "credential window unavailable (headless session?)"
        case .unknownProfile(let profile): "unknown credential profile: \(profile)"
        case .missingField(let fields): "credential is missing required field(s): \(fields)"
        case .keychain(let status): "keychain error: \(status)"
        case .executableNotFound(let name): "executable not found: \(name)"
        }
    }
}
