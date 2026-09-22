import Foundation
import CommandKit

/// Durable credential profiles. Secret values never leave the store/runner boundary.
public struct CredentialBroker: Sendable {
    private let store: any CredentialStoring
    private let runner: CommandRunning
    private let prompt: @Sendable (CredentialSpec) async -> CredentialPromptOutcome

    public init(store: any CredentialStoring, runner: CommandRunning = ProcessCommandRunner(), prompt: @escaping @Sendable (CredentialSpec) async -> CredentialPromptOutcome) {
        self.store = store; self.runner = runner; self.prompt = prompt
    }

    public func requestCredential(_ spec: CredentialSpec) async throws -> CredentialRequestResult {
        switch await prompt(spec) {
        case .cancelled: throw CredentialError.declined
        case .unavailable: throw CredentialError.promptUnavailable
        case .saved(let values):
            let secretKeys = spec.fields.filter(\.secret).map(\.key)
            let stored = spec.storage == .keychain
            if stored { try await saveCredential(profile: spec.profile, fields: values, fieldOrder: spec.fields.map(\.key), secretKeys: secretKeys, meta: spec.meta) }
            var verified: Bool?; var message = ""
            if let verify = spec.verify { let result = await runVerify(verify, fields: values, secretKeys: secretKeys); verified = result.0; message = result.1 }
            return CredentialRequestResult(info: .init(profile: spec.profile, fields: spec.fields.map(\.key), source: spec.meta["source"]), stored: stored, verified: verified, message: message)
        }
    }

    /// Handles transient input inside the caller's secure workflow without persisting or returning it.
    /// Use only for a one-shot provisioner; normal callers should use `requestCredential`.
    public func withTransientCredential<Result: Sendable>(_ spec: CredentialSpec, operation: @escaping @Sendable ([String: String]) async throws -> Result) async throws -> Result {
        switch await prompt(spec) {
        case .cancelled: throw CredentialError.declined
        case .unavailable: throw CredentialError.promptUnavailable
        case .saved(let values): return try await operation(values)
        }
    }

    /// Stores a value only in the injected secure store; the result contains metadata, never values.
    public func saveCredential(profile: String, fields: [String: String], fieldOrder: [String], secretKeys: [String], meta: [String: String]) async throws {
        try await store.save(profile, .init(fields: fields, fieldOrder: fieldOrder, secretKeys: secretKeys, meta: meta))
    }

    public func listCredentials() async throws -> [CredentialInfo] {
        var result: [CredentialInfo] = []
        for profile in try await store.profiles() {
            guard let credential = try await store.load(profile) else { continue }
            result.append(CredentialInfo(profile: profile, fields: credential.fieldOrder, source: credential.meta["source"]))
        }
        return result
    }

    @discardableResult public func forgetCredential(_ profile: String) async throws -> Bool {
        let existed = try await store.load(profile) != nil; try await store.delete(profile); return existed
    }

    public func runWithCredential(profile: String, command: String, args: [String]) async throws -> CommandResult {
        guard let credential = try await store.load(profile) else { throw CredentialError.unknownProfile(profile) }
        let result = await runner.run(command, Placeholder.substituteFields(args: args, fields: credential.fields))
        let secrets = credential.secretKeys.compactMap { credential.fields[$0] }
        return CommandResult(stdout: Redactor.redact(result.stdout, values: secrets), stderr: Redactor.redact(result.stderr, values: secrets), exitCode: result.exitCode)
    }

    public func infisicalRun(profile: String, bin: String, args: [String], domain: String?) async throws -> CommandResult {
        guard let credential = try await store.load(profile) else { throw CredentialError.unknownProfile(profile) }
        guard let id = credential.fields["client_id"], let secret = credential.fields["client_secret"] else { throw CredentialError.missingField("client_id, client_secret") }
        var login = ["login", "--method=universal-auth", "--client-id", id, "--client-secret", secret, "--plain", "--silent"]
        if let domain, !domain.isEmpty { login += ["--domain", domain] }
        let loginResult = await runner.run(bin, login)
        guard loginResult.ok else { return .init(stdout: "", stderr: Redactor.redact("infisical login failed: " + loginResult.stderr, values: [id, secret]), exitCode: loginResult.exitCode) }
        let token = loginResult.trimmedStdout
        var command = args + ["--token", token]
        if let domain, !domain.isEmpty { command += ["--domain", domain] }
        let result = await runner.run(bin, command)
        return .init(stdout: Redactor.redact(result.stdout, values: [id, secret, token]), stderr: Redactor.redact(result.stderr, values: [id, secret, token]), exitCode: result.exitCode)
    }

    public static func normalizeToken(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = Data(base64Encoded: trimmed) {
            do {
                if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let token = object["JTWToken"] as? String, !token.isEmpty {
                    return token
                }
            } catch {
                // not a valid JSON payload
            }
        }
        return trimmed
    }

    private func runVerify(_ verify: CredentialVerify, fields: [String: String], secretKeys: [String]) async -> (Bool, String) {
        let result = await runner.run(verify.command, Placeholder.substituteFields(args: verify.args, fields: fields))
        let ok = result.ok && (verify.successContains.map { result.stdout.contains($0) || result.stderr.contains($0) } ?? true)
        let values = secretKeys.compactMap { fields[$0] }
        return (ok, String(Redactor.redact(ok ? "verified" : "failed: " + result.stderr + result.stdout, values: values).prefix(500)))
    }
}
