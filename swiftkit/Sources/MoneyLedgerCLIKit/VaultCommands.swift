import Foundation
import MoneyLedgerKit

/// vault 서브커맨드 — 민감정보는 Vaultwarden Secure Note 로만. 비밀값 입력은 stdin 전용.
enum VaultCommands {
    /// 한 호출의 금고 창구. 우리 Vaultwarden Client 앱이 열려 있으면 그 창구를 쓴다 — 별도 로그인 불필요.
    private struct Session {
        let context: LedgerContext
        let vault: LedgerVault
        let docsVault: VaultDocsGateway
        let appStatus: VaultDocsGateway.Status
        let json: Bool
        let output: CLIOutput

        var appReady: Bool { appStatus == .ready }
    }

    static func run(
        context: LedgerContext, sub: [String], scanner: ArgScanner, json: Bool,
        output: CLIOutput, environment: [String: String]
    ) async throws {
        let action = sub.first ?? "status"
        let docsVault = VaultDocsGateway()
        let session = Session(
            context: context,
            vault: LedgerVault(context: context, environment: environment),
            docsVault: docsVault,
            appStatus: await docsVault.status(),
            json: json,
            output: output
        )
        switch action {
        case "status":
            await status(session)
        case "login":
            try await login(session, sub: sub)
        case "link":
            try await link(session, sub: sub)
        case "show":
            try await show(session, sub: sub, reveal: scanner.has("reveal"))
        case "unlink":
            try await unlink(session, sub: sub, deleteNote: scanner.has("delete-note"))
        default:
            throw UsageError("unknown: vault \(action)")
        }
    }

    private static func status(_ session: Session) async {
        let status = await session.vault.status()
        if session.json {
            var object: [String: Any] = [
                "status": status.rawValue,
                "vaultAppStatus": session.appStatus.rawValue,
                "activeBackend": session.appReady ? "vaultwarden-client" : "session",
            ]
            if let email = await session.vault.accountEmail() { object["email"] = email }
            if let server = await session.vault.serverURL() { object["server"] = server }
            session.output.okJSON(object)
            return
        }
        guard !session.appReady else {
            session.output.out("vault: 연결됨 — Vaultwarden Client 앱 경유")
            return
        }
        let label: String
        switch status {
        case .available: label = "연결됨(해제 상태)"
        case .locked: label = "잠김 — \(session.context.masterPasswordEnvKey) 또는 Touch ID 로 해제"
        case .unconfigured: label = "미설정 — vault login <server> <email> (비밀번호는 stdin)"
        }
        session.output.out("vault: \(label)")
        session.output.out("금고 앱: \(session.appStatus.korean)")
    }

    private static func login(_ session: Session, sub: [String]) async throws {
        guard sub.count >= 3 else {
            throw UsageError("vault login <server|us|eu> <email> (마스터 비밀번호는 stdin)")
        }
        guard let password = readSecretFromStdin(), !password.isEmpty else {
            throw UsageError("마스터 비밀번호를 stdin 으로 넣으세요: echo \"$PW\" | … vault login <server> <email>")
        }
        try await session.vault.login(server: sub[1], email: sub[2], password: password)
        if session.json { session.output.okJSON(["loggedIn": true]) } else { session.output.out("로그인 완료") }
    }

    private static func link(_ session: Session, sub: [String]) async throws {
        let (entity, ref) = try entityRef(sub, "link")
        guard let secret = readSecretFromStdin(), !secret.isEmpty else {
            throw UsageError("민감값(전체 계좌/카드번호 등)을 stdin 으로 넣으세요")
        }
        let store = try LedgerStore(context: session.context)
        let noteRef: String
        switch entity {
        case "account":
            var account = try await store.resolveAccount(ref)
            account.vaultNoteRef = try await storeSecret(session, entity: entity, id: account.id, text: secret)
            try await store.save(account: account)
            noteRef = account.vaultNoteRef ?? ""
        case "card":
            var card = try await store.resolveCard(ref)
            card.vaultNoteRef = try await storeSecret(session, entity: entity, id: card.id, text: secret)
            try await store.save(card: card)
            noteRef = card.vaultNoteRef ?? ""
        default:
            throw UsageError("vault link account|card <id|이름>")
        }
        if session.json {
            session.output.okJSON(["linked": noteRef])
        } else {
            session.output.out("보관됨 → \(noteRef) (원장에는 참조만 남음)")
        }
    }

    private static func show(_ session: Session, sub: [String], reveal: Bool) async throws {
        let (entity, ref) = try entityRef(sub, "show")
        let store = try LedgerStore(context: session.context)
        let linked: String?
        switch entity {
        case "account": linked = try await store.resolveAccount(ref).vaultNoteRef
        case "card": linked = try await store.resolveCard(ref).vaultNoteRef
        default: throw UsageError("vault show account|card <id|이름>")
        }
        guard let noteRef = linked else {
            throw UsageError("연결된 민감정보가 없습니다 — vault link \(entity) \(ref) 먼저")
        }
        let secret = try await readSecret(session, noteRef: noteRef)
        if reveal {
            // 파이프 소비용 원문 — 마스킹 없이 그대로.
            if session.json { session.output.okJSON(["value": secret]) } else { session.output.out(secret) }
            return
        }
        let masked = mask(secret)
        if session.json {
            session.output.okJSON(["masked": masked, "noteRef": noteRef])
        } else {
            session.output.out("\(masked)  (원문은 --reveal)")
        }
    }

    private static func unlink(_ session: Session, sub: [String], deleteNote: Bool) async throws {
        let (entity, ref) = try entityRef(sub, "unlink")
        let store = try LedgerStore(context: session.context)
        let linked: String?
        switch entity {
        case "account":
            var account = try await store.resolveAccount(ref)
            linked = account.vaultNoteRef
            account.vaultNoteRef = nil
            try await store.save(account: account)
        case "card":
            var card = try await store.resolveCard(ref)
            linked = card.vaultNoteRef
            card.vaultNoteRef = nil
            try await store.save(card: card)
        default:
            throw UsageError("vault unlink account|card <id|이름>")
        }
        if deleteNote, let noteRef = linked {
            try await deleteSecret(session, noteRef: noteRef)
        }
        if session.json { session.output.okJSON(["unlinked": true]) } else { session.output.out("연결 해제됨") }
    }

    /// 금고 앱 창구가 열려 있으면 그리로, 아니면 자체 VaultSession 으로 저장. 노트 이름 계약은 동일.
    private static func storeSecret(
        _ session: Session, entity: String, id: String, text: String
    ) async throws -> String {
        guard session.appReady else {
            return try await session.vault.storeSecret(entity: entity, id: id, text: text)
        }
        let name = session.context.vaultNoteName(entity: entity, id: id)
        try await session.docsVault.setNote(name: name, text: text)
        return name
    }

    private static func readSecret(_ session: Session, noteRef: String) async throws -> String {
        let text: String?
        if session.appReady {
            text = try await session.docsVault.note(name: noteRef)
        } else {
            text = try await session.vault.readSecret(noteRef: noteRef)
        }
        guard let text else { throw VaultReadError.noteMissing(noteRef) }
        return text
    }

    private static func deleteSecret(_ session: Session, noteRef: String) async throws {
        if session.appReady {
            _ = try await session.docsVault.deleteNote(name: noteRef)
        } else {
            _ = try await session.vault.deleteSecret(noteRef: noteRef)
        }
    }

    private static func mask(_ secret: String) -> String {
        guard secret.count > 4 else { return "••••" }
        return String(repeating: "•", count: max(4, secret.count - 4)) + secret.suffix(4)
    }

    private static func entityRef(_ sub: [String], _ action: String) throws -> (String, String) {
        guard sub.count >= 3 else { throw UsageError("vault \(action) account|card <id|이름>") }
        return (sub[1], sub[2])
    }
}

enum VaultReadError: Error, CustomStringConvertible {
    case noteMissing(String)

    var description: String {
        switch self {
        case let .noteMissing(ref): "Vault 에 노트가 없습니다: \(ref) (삭제됐거나 다른 계정)"
        }
    }
}
