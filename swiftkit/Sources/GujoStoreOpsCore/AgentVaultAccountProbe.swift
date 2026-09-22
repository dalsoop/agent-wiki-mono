import InteropKit
import Foundation
import LocalizationKit
import CommandKit


/// Agent Vault 테넌트·계정 카드 메타(비밀 제외). Store Ops 설정 UI / CLI 정본 조회.
public enum AgentVaultAccountProbe: Sendable {
    public static let productTenantSlug = "gujo"
    public static let productTenantID = "tenant:gujo"

    public struct TenantRow: Sendable, Equatable, Codable {
        public var id: String
        public var slug: String
        public var name: String
        public var isActive: Bool
        public var purpose: String
        public var agentCount: Int

        public init(id: String, slug: String, name: String, isActive: Bool, purpose: String, agentCount: Int) {
            self.id = id
            self.slug = slug
            self.name = name
            self.isActive = isActive
            self.purpose = purpose
            self.agentCount = agentCount
        }

        public var headline: String {
            let flag = isActive ? "active" : "inactive"
            return "\(id)  \(name)  \(flag)  agents=\(agentCount)"
        }
    }

    public struct CredentialRow: Sendable, Equatable, Codable {
        public var id: String
        public var name: String
        public var kind: String
        public var account: String
        public var host: String
        public var ownerTenantID: String
        public var secretStored: Bool

        public init(
            id: String,
            name: String,
            kind: String,
            account: String,
            host: String,
            ownerTenantID: String,
            secretStored: Bool
        ) {
            self.id = id
            self.name = name
            self.kind = kind
            self.account = account
            self.host = host
            self.ownerTenantID = ownerTenantID
            self.secretStored = secretStored
        }

        public var line: String {
            let secret = secretStored ? "stored" : "missing"
            return "\(name)\t\(kind)\t\(account)\towner=\(ownerTenantID)\t\(secret)"
        }
    }

    public struct Snapshot: Sendable, Equatable {
        public var tenants: [TenantRow]
        public var credentials: [CredentialRow]
        public var productTenant: TenantRow?
        public var vaultAvailable: Bool
        public var error: String?

        public init(
            tenants: [TenantRow] = [],
            credentials: [CredentialRow] = [],
            productTenant: TenantRow? = nil,
            vaultAvailable: Bool = false,
            error: String? = nil
        ) {
            self.tenants = tenants
            self.credentials = credentials
            self.productTenant = productTenant
            self.vaultAvailable = vaultAvailable
            self.error = error
        }

        public var headline: String {
            if let error {
                return "vault error: \(error)"
            }
            guard vaultAvailable else { return CLILocalization.string("AgentVaultAccountProbe.return") }
            let t = productTenant.map { "\($0.name)(\($0.isActive ? "active" : "ok"))" } ?? CLILocalization.string("AgentVaultAccountProbe.string-2")
            return CLILocalization.format("AgentVaultAccountProbe.return-2", t, credentials.count)
        }
    }

    // MARK: - Parse (testable)

    public static func parseTenants(json data: Data) throws -> [TenantRow] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let arr = (root?["result"] as? [[String: Any]]) ?? []
        return arr.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let slug = (row["slug"] as? String) ?? id.replacingOccurrences(of: "tenant:", with: "")
            let name = (row["name"] as? String) ?? slug
            let isActive = (row["isActive"] as? Bool) ?? false
            let purpose = (row["purpose"] as? String) ?? ""
            let agents = (row["agentIDs"] as? [Any]) ?? []
            return TenantRow(
                id: id,
                slug: slug,
                name: name,
                isActive: isActive,
                purpose: purpose,
                agentCount: agents.count
            )
        }
    }

    public static func parseCredentials(json data: Data) throws -> [CredentialRow] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let arr = (root?["result"] as? [[String: Any]]) ?? []
        return arr.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return CredentialRow(
                id: id,
                name: (row["name"] as? String) ?? id,
                kind: (row["kind"] as? String) ?? "",
                account: (row["account"] as? String) ?? "",
                host: (row["host"] as? String) ?? "",
                ownerTenantID: (row["ownerTenantID"] as? String) ?? "",
                secretStored: (row["secretStored"] as? Bool) ?? false
            )
        }
    }

    // MARK: - Live probe

    /// `agent-vault` CLI 로 tenant list + credential list --tenant gujo (비밀 미출력).
    public static func snapshot(
        vaultPath: String? = nil,
        run: ((String, [String]) throws -> Data)? = nil
    ) -> Snapshot {
        let path = vaultPath ?? resolveVaultBinary()
        guard let path else {
            return Snapshot(error: "agent-vault 바이너리 없음 (PATH 또는 /opt/homebrew/bin)")
        }
        let exec: (String, [String]) throws -> Data = run ?? { bin, args in
            try runProcess(path: bin, args: args)
        }
        do {
            let tData = try exec(path, ["tenant", "list", "--json"])
            let tenants = try parseTenants(json: tData)
            let cData = try exec(path, ["credential", "list", "--tenant", productTenantSlug, "--json"])
            let creds = try parseCredentials(json: cData)
            let product = tenants.first { $0.id == productTenantID || $0.slug == productTenantSlug }
            return Snapshot(
                tenants: tenants,
                credentials: creds,
                productTenant: product,
                vaultAvailable: true,
                error: nil
            )
        } catch {
            return Snapshot(vaultAvailable: true, error: error.localizedDescription)
        }
    }

    public static func plainText(_ snap: Snapshot = snapshot()) -> String {
        var lines: [String] = []
        lines.append(CLILocalization.format("AgentVaultAccountProbe.string", "\(productTenantID)"))
        lines.append(snap.headline)
        if let e = snap.error {
            lines.append("error: \(e)")
            return lines.joined(separator: "\n")
        }
        lines.append("--- tenants ---")
        for t in snap.tenants {
            let mark = t.id == productTenantID ? "*" : " "
            lines.append("\(mark) \(t.headline)")
            if !t.purpose.isEmpty { lines.append("    \(t.purpose)") }
        }
        lines.append("--- credentials \(productTenantID) ---")
        if snap.credentials.isEmpty {
            lines.append("(없음)")
        } else {
            for c in snap.credentials {
                lines.append(c.line)
                if !c.host.isEmpty { lines.append("    host \(c.host)") }
            }
        }
        lines.append("정본: agent-vault tenant|credential · AgentVaultAccountProbe")
        return lines.joined(separator: "\n")
    }

    // MARK: - Process

    private static func resolveVaultBinary() -> String? {
        let candidates = [
            HostPlatform.cliBinPath("agent-vault"),
            StoreOpsPaths.usrLocalCLI("agent-vault"),
            (ProcessInfo.processInfo.environment["HOME"] ?? "") + "/.local/bin/agent-vault",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) {
            return p
        }
        // PATH which
        do {
            let data = try runProcess(path: "/usr/bin/which", args: ["agent-vault"])
            if let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty,
               FileManager.default.isExecutableFile(atPath: s)
            {
                return s
            }
        } catch {}
        return nil
    }

    private static let processTimeoutSeconds: TimeInterval = 8

    private static func runProcess(path: String, args: [String]) throws -> Data {
        let result = SafeProcessRunner.run(
            executable: path,
            arguments: args,
            timeout: processTimeoutSeconds
        )
        if result.exitCode != 0 {
            let e = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "AgentVaultAccountProbe",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: e.isEmpty ? "exit \(result.exitCode)" : e]
            )
        }
        return Data(result.stdout.utf8)
    }
}

