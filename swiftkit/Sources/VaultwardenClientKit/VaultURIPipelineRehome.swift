import Foundation

extension VaultURIPipeline {
    public static func rehomeScan(items: [VaultItem]) -> Snapshot {
        let logins = items.filter { !$0.deleted && $0.isLogin }
        let rows: [Row] = logins.compactMap { item in
            guard shouldRehomeToNote(item) else { return nil }
            return Row(
                itemID: item.id,
                itemName: item.name,
                proposedURI: item.loginURIs.joined(separator: "\n"),
                reason: rehomeReason(item)
            )
        }
        .sorted { $0.itemName.localizedCaseInsensitiveCompare($1.itemName) == .orderedAscending }
        return Snapshot(
            loginCount: logins.count,
            presentCount: logins.filter { !shouldRehomeToNote($0) }.count,
            rows: rows
        )
    }

    public static func rehomeReason(_ item: VaultItem) -> String {
        let name = item.name.lowercased()
        if name.contains("ssh") { return "SSH → 메모" }
        if item.loginURIs.contains(where: { ($0.lowercased().contains(".local") || endpointHost(of: $0) == "localhost") }) {
            return "로컬 호스트 → 메모"
        }
        if item.loginURIs.contains(where: { endpointHost(of: $0).map(isIPv4) ?? false }) {
            return "IP/인프라 → 메모"
        }
        return "인프라 로그인 → 메모"
    }

    /// 로그인 자격은 메모 본문으로 옮긴다. 웹 원장 필드는 버린다.
    public static func noteFromLogin(_ item: VaultItem) -> VaultItem {
        var note = VaultItem(
            core: .init(
                id: "",
                type: 2,
                name: item.name,
                notes: credentialNote(from: item),
                favorite: item.favorite,
                folderId: item.folderId
            ),
            extras: .init(
                fields: item.fields.filter { $0.name != ledgerFieldName },
                organizationId: item.organizationId,
                collectionIds: item.collectionIds
            )
        )
        var tags = note.tags
        let extra = item.name.lowercased().contains("ssh") ? "SSH" : "서버"
        if !tags.contains(where: { $0.caseInsensitiveCompare(extra) == .orderedSame }) {
            tags.append(extra)
        }
        note.tags = tags
        return VaultPlacement.apply(note)
    }

    // MARK: - unhome (메모 → 로그인 역변환)

    public struct ParsedCredentialNote: Sendable {
        public let username: String
        public let password: String
        public let totp: String?
        public let uris: [String]
        public let trailingNotes: String
    }

    public static func parseCredentialNote(_ notes: String) -> ParsedCredentialNote? {
        guard notes.contains("[인프라 로그인 → 메모]") || notes.contains("아이디:") else { return nil }
        var username = ""
        var password = ""
        var totp: String?
        var uris: [String] = []
        var trailing: [String] = []
        var pastHeader = false
        for line in notes.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[인프라 로그인 → 메모]" { continue }
            if trimmed.hasPrefix("아이디:") { username = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces); pastHeader = true; continue }
            if trimmed.hasPrefix("비밀번호:") { password = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces); pastHeader = true; continue }
            if trimmed.hasPrefix("TOTP:") { totp = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces); pastHeader = true; continue }
            if trimmed.hasPrefix("호스트:") { uris.append(String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)); pastHeader = true; continue }
            if pastHeader && !trimmed.isEmpty { trailing.append(line) }
        }
        if username.isEmpty && password.isEmpty { return nil }
        return ParsedCredentialNote(username: username, password: password, totp: totp, uris: uris, trailingNotes: trailing.joined(separator: "\n"))
    }

    public static func shouldUnhomeToLogin(_ item: VaultItem) -> Bool {
        guard item.type == 2, !item.deleted else { return false }
        return parseCredentialNote(item.notes) != nil
    }

    public static func unhomeScan(items: [VaultItem]) -> Snapshot {
        let notes = items.filter { $0.type == 2 && !$0.deleted }
        let rows: [Row] = notes.compactMap { item in
            guard shouldUnhomeToLogin(item),
                  let parsed = parseCredentialNote(item.notes) else { return nil }
            return Row(
                itemID: item.id,
                itemName: item.name,
                proposedURI: parsed.uris.joined(separator: "\n"),
                reason: "메모 → 로그인"
            )
        }
        .sorted { $0.itemName.localizedCaseInsensitiveCompare($1.itemName) == .orderedAscending }
        return Snapshot(
            loginCount: items.filter { $0.isLogin && !$0.deleted }.count,
            presentCount: rows.count,
            rows: rows
        )
    }

    public static func loginFromNote(_ item: VaultItem) -> VaultItem? {
        guard let parsed = parseCredentialNote(item.notes) else { return nil }
        var login = VaultItem(
            core: .init(
                id: "",
                type: 1,
                name: item.name,
                notes: parsed.trailingNotes,
                favorite: item.favorite,
                folderId: item.folderId
            ),
            login: .init(
                username: parsed.username,
                password: parsed.password,
                uri: parsed.uris.first ?? "",
                uris: parsed.uris,
                totp: parsed.totp
            ),
            extras: .init(
                fields: item.fields,
                organizationId: item.organizationId,
                collectionIds: item.collectionIds
            )
        )
        login.tags = item.tags.filter { $0 != "서버" && $0 != "SSH" && $0 != "메모" }
        return login
    }

    public static func credentialNote(from item: VaultItem) -> String {
        var lines: [String] = ["[인프라 로그인 → 메모]"]
        if !item.username.isEmpty { lines.append("아이디: \(item.username)") }
        if !item.password.isEmpty { lines.append("비밀번호: \(item.password)") }
        if let totp = item.totp, !totp.isEmpty { lines.append("TOTP: \(totp)") }
        for uri in item.loginURIs { lines.append("호스트: \(uri)") }
        if !item.notes.isEmpty {
            lines.append("")
            lines.append(item.notes)
        }
        return lines.joined(separator: "\n")
    }
}
