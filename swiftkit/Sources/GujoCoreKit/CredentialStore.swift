import Foundation

/// 앱이 저장하는 접속 설정. **비밀은 없다** (#28 D1/D4).
/// API key 는 Agent Vault 에만 있고, 앱은 카드 ID 하나만 들고 있다.
public struct Credentials: Sendable {
    /// Agent Vault 카드 ID. 비밀이 아니므로 평문 config 로 충분하다.
    public let vaultCredentialID: String?
    public let baseURL: String?

    public init(vaultCredentialID: String?, baseURL: String?) {
        self.vaultCredentialID = vaultCredentialID
        self.baseURL = baseURL
    }

    public var isReady: Bool {
        guard let vaultCredentialID,
              !vaultCredentialID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        guard let baseURL,
              let components = URLComponents(string: baseURL),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return false }
        return true
    }
}

public final class CredentialStore: Sendable {
    static let filePOSIXPermissions: Int = 0o600

    private let file: URL
    private let access: LedgerWriteAccess
    public init(file: URL = AppPaths.credentialsFile, access: LedgerWriteAccess = .cloudApps) {
        self.file = file
        self.access = access
    }

    public func load() -> Credentials {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return Credentials(vaultCredentialID: nil, baseURL: nil)
        }
        let text: String
        do {
            text = try String(contentsOf: file, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(
                Data("warning: failed to read credentials: \(error)\n".utf8))
            return Credentials(vaultCredentialID: nil, baseURL: nil)
        }
        var map: [String: String] = [:]
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            map[key] = value
        }
        // 레거시 `GUJO_API_KEY` 는 읽지 않는다. 다음 save 에서 파일째 덮어써져 사라진다.
        return Credentials(
            vaultCredentialID: map["GUJO_VAULT_CREDENTIAL_ID"],
            baseURL: map["GUJO_BASE_URL"])
    }

    public func save(vaultCredentialID: String, baseURL: String) throws {
        guard access.allowsWrite else { throw LedgerWriteDenied.retiredOwner }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = "GUJO_VAULT_CREDENTIAL_ID=\(vaultCredentialID)\nGUJO_BASE_URL=\(baseURL)\n"
        try body.write(to: file, atomically: true, encoding: .utf8)
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: CredentialStore.filePOSIXPermissions],
                ofItemAtPath: file.path)
        } catch {
            FileHandle.standardError.write(
                Data("warning: credentials chmod failed: \(error)\n".utf8))
        }
    }

    public func clear() throws {
        guard access.allowsWrite else { throw LedgerWriteDenied.retiredOwner }
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
