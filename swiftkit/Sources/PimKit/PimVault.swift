import Foundation
import StateRootKit

/// 공용 PIM vault — 스위트 전 앱이 같은 디렉터리의 JSON 파일을 정본으로 공유한다.
///
/// 레이아웃:
///   ~/PimVault/events.json     [CalendarEvent]
///   ~/PimVault/todos.json      [TodoItem]
///   ~/PimVault/contacts.json   [Contact]
///   ~/PimVault/notes.json      [Note]
///   ~/PimVault/mail/accounts.json  [MailAccount]
///   ~/PimVault/mail/messages.json  [MailMessage]
///
/// 루트는 `PIM_VAULT_ROOT` 환경변수로 오버라이드(테스트·격리 실행).
/// 미지정 시 StateRootKit 5단계 캐스케이드(SWIFT_APP_STATE_ROOT → 테스트 러너 → 테넌트 컨텍스트 → ~/PimVault)로 자동 격리.
/// 쓰기는 temp 파일 + rename 의 원자적 교체. 날짜는 ISO8601 로 고정해
/// 사람이 vault 를 직접 읽고 diff 할 수 있게 한다.
public struct PimVault: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// 기본 vault — PIM_VAULT_ROOT 없으면 StateRootKit 캐스케이드(~/PimVault).
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> PimVault {
        if let override = environment["PIM_VAULT_ROOT"], !override.isEmpty {
            return PimVault(root: URL(fileURLWithPath: (override as NSString).expandingTildeInPath))
        }
        return PimVault(root: StateRootKit.url("PimVault", environment: environment))
    }

    // MARK: - 컬렉션 파일 경로

    public var eventsFile: URL { root.appendingPathComponent("events.json") }
    public var todosFile: URL { root.appendingPathComponent("todos.json") }
    public var contactsFile: URL { root.appendingPathComponent("contacts.json") }
    public var notesFile: URL { root.appendingPathComponent("notes.json") }
    public var mailAccountsFile: URL { root.appendingPathComponent("mail/accounts.json") }
    public var mailMessagesFile: URL { root.appendingPathComponent("mail/messages.json") }

    // MARK: - JSON 코덱 (ISO8601 고정)

    public static func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }

    public static func decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    // MARK: - 로드/저장

    /// 파일이 없으면 빈 배열 — 첫 실행에서 vault 를 미리 만들 필요가 없다.
    public func load<T: Codable>(_ type: [T].Type, from file: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let data = try Data(contentsOf: file)
        guard !data.isEmpty else { return [] }
        return try Self.decoder().decode([T].self, from: data)
    }

    /// 원자적 저장: 같은 디렉터리의 temp 파일에 쓰고 rename 으로 교체 (심링크 보존).
    public func save<T: Codable>(_ items: [T], to file: URL) throws {
        let resolved = file.resolvingSymlinksInPath()
        let dir = resolved.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try Self.encoder().encode(items)
        let tmp = dir.appendingPathComponent(".\(resolved.lastPathComponent).tmp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try data.write(to: tmp)
        if FileManager.default.fileExists(atPath: resolved.path) {
            _ = try FileManager.default.replaceItemAt(resolved, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: file)
        }
    }

    /// `save(to:)` 자체는 temp+rename 으로 원자적이지만, 여러 프로세스가 `load → 수정 →
    /// save` 를 lock 없이 반복하면 논리적 lost update 가 생긴다 — 실측: pim-mail GUI(사용자
    /// 읽음 표시 등)와 pim-mail-automation(LaunchAgent tick)이 같은 `mail/messages.json`
    /// 을 동시에 건드릴 수 있는 유일한 조합이라, 새 메일을 받아온 automation 의 저장과
    /// GUI 의 상태 변경 저장이 서로를 덮어쓸 수 있었다. 파일별로 독립된 `.lock` 을 둬서
    /// mail 저장 경쟁이 다른 컬렉션(캘린더·todo 등) 접근을 막지 않게 한다.
    public func withExclusiveAccess<T>(to file: URL, _ body: () throws -> T) throws -> T {
        let dir = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let lockFile = dir.appendingPathComponent(".\(file.lastPathComponent).lock")
        let fd = open(lockFile.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw PimVaultError.lockFailed(file.lastPathComponent) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw PimVaultError.lockFailed(file.lastPathComponent) }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    // MARK: - 도메인별 편의

    public func loadEvents() throws -> [CalendarEvent] { try load([CalendarEvent].self, from: eventsFile) }
    public func saveEvents(_ items: [CalendarEvent]) throws { try save(items, to: eventsFile) }

    public func loadTodos() throws -> [TodoItem] { try load([TodoItem].self, from: todosFile) }
    public func saveTodos(_ items: [TodoItem]) throws { try save(items, to: todosFile) }

    public func loadContacts() throws -> [Contact] { try load([Contact].self, from: contactsFile) }
    public func saveContacts(_ items: [Contact]) throws { try save(items, to: contactsFile) }

    public func loadNotes() throws -> [Note] { try load([Note].self, from: notesFile) }
    public func saveNotes(_ items: [Note]) throws { try save(items, to: notesFile) }

    public func loadMailAccounts() throws -> [MailAccount] { try load([MailAccount].self, from: mailAccountsFile) }
    public func saveMailAccounts(_ items: [MailAccount]) throws { try save(items, to: mailAccountsFile) }

    public func loadMailMessages() throws -> [MailMessage] { try load([MailMessage].self, from: mailMessagesFile) }
    public func saveMailMessages(_ items: [MailMessage]) throws { try save(items, to: mailMessagesFile) }

    /// mail messages 의 read-modify-write 구간을 프로세스 간 직렬화한다. GUI와
    /// automation(LaunchAgent)이 동시에 메일 상태를 바꿀 수 있는 유일한 PimVault
    /// 컬렉션이라 여기에만 우선 적용한다.
    public func withExclusiveMailAccess<T>(_ body: (_ load: () throws -> [MailMessage], _ save: ([MailMessage]) throws -> Void) throws -> T) throws -> T {
        try withExclusiveAccess(to: mailMessagesFile) {
            try body({ try self.loadMailMessages() }, { try self.saveMailMessages($0) })
        }
    }
}

extension PimVault {
    /// id 접두 매칭 — CLI 에서 UUID 전체 대신 앞 몇 글자로 지정.
    /// 유일하게 결정되지 않으면 에러(모호), 없으면 nil.
    public static func match<T: Identifiable>(_ items: [T], idPrefix: String) throws -> T? where T.ID == String {
        if let exact = items.first(where: { $0.id == idPrefix }) { return exact }
        let hits = items.filter { $0.id.lowercased().hasPrefix(idPrefix.lowercased()) }
        if hits.count > 1 {
            throw PimVaultError.ambiguousID(prefix: idPrefix, count: hits.count)
        }
        return hits.first
    }
}

public enum PimVaultError: Error, LocalizedError, Equatable {
    case ambiguousID(prefix: String, count: Int)
    case notFound(String)
    case lockFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .ambiguousID(prefix, count):
            return "id prefix '\(prefix)' matches \(count) items — use more characters"
        case let .notFound(what):
            return "\(what) not found"
        case let .lockFailed(file):
            return "vault lock 획득 실패: \(file)"
        }
    }
}
