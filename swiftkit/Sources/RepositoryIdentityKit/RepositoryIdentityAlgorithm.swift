#if canImport(CryptoKit)
import CryptoKit
import Foundation

/// Canonical repository join-key algorithm shared by repository owners and runtime consumers.
///
/// The version changes only when normalization or digest semantics change. Callers may keep their
/// existing JSON model and field spelling (`repoId`/`repoID`) while delegating identity derivation
/// here.
public enum RepositoryIdentityAlgorithm {
    public static let version = "repository-identity.v1"
    public static let repoIDPrefix = "repo-sha256-"

    public static func normalize(remoteURL raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw RepositoryRemoteError.missingRemote }

        if value.hasPrefix("/") || value.hasPrefix("./") || value.hasPrefix("../") {
            let path = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
                .standardizedFileURL.path
            return "file://" + stripGitSuffix(path)
        }

        // SCP-style Git URL: git@host:owner/repository.git
        if !value.contains("://"),
           let colon = value.firstIndex(of: ":"),
           !value[..<colon].contains("/") {
            let authority = String(value[..<colon])
            let path = String(value[value.index(after: colon)...])
            let host = authority.split(separator: "@").last.map(String.init) ?? authority
            return canonical(host: host, port: nil, path: path)
        }

        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased() else {
            throw RepositoryRemoteError.invalidRemote(value)
        }
        if scheme == "file" {
            return "file://" + stripGitSuffix(
                URL(fileURLWithPath: components.path).standardizedFileURL.path)
        }
        guard let host = components.host, !host.isEmpty else {
            throw RepositoryRemoteError.invalidRemote(value)
        }
        let defaultPort = (scheme == "ssh" && components.port == 22)
            || (scheme == "https" && components.port == 443)
            || (scheme == "http" && components.port == 80)
        return canonical(host: host, port: defaultPort ? nil : components.port, path: components.path)
    }

    public static func repoID(remoteURL: String) throws -> String {
        repoID(normalizedRemote: try normalize(remoteURL: remoteURL))
    }

    public static func repoID(normalizedRemote: String) -> String {
        let digest = SHA256.hash(data: Data(normalizedRemote.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return repoIDPrefix + digest
    }

    public static func isCanonicalRepoID(_ value: String) -> Bool {
        guard value.hasPrefix(repoIDPrefix) else { return false }
        let digest = value.dropFirst(repoIDPrefix.count)
        return digest.count == 64 && digest.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private static func canonical(host: String, port: Int?, path: String) -> String {
        let authority = host.lowercased() + (port.map { ":\($0)" } ?? "")
        let decoded = path.removingPercentEncoding ?? path
        let cleanPath = stripGitSuffix(decoded)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return authority + "/" + cleanPath
    }

    private static func stripGitSuffix(_ path: String) -> String {
        var result = path
        while result.count > 1 && result.hasSuffix("/") { result.removeLast() }
        if result.lowercased().hasSuffix(".git") { result.removeLast(4) }
        return result
    }
}

public enum RepositoryRemoteError: Error, Sendable, Equatable {
    case missingRemote
    case invalidRemote(String)
}
#endif
