import Foundation
import Testing
@testable import PimKit

private func tempVault() throws -> PimVault {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PimKitTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return PimVault(root: dir)
}

@Suite struct PimVaultTests {
    @Test func mailAccountDecodesLegacyPayloadWithDefaults() throws {
        let data = Data(#"{"id":"legacy","name":"icloud","host":"imap.example.com","port":993,"username":"me","passwordCommand":"echo pw"}"#.utf8)
        let account = try PimVault.decoder().decode(MailAccount.self, from: data)
        #expect(account.provider == .custom)
        #expect(account.browserProfile == nil)
        #expect(account.browserSession == nil)
        #expect(account.authState == .unknown)
        #expect(account.vaultCredentialID == nil)
    }

    @Test func mailAccountRoundTripsVaultCredentialPin() throws {
        let account = MailAccount(
            name: "work",
            host: "imap.example.com",
            username: "me",
            passwordCommand: "keychain:id",
            auth: .init(vaultCredentialID: "vault-card-1")
        )
        let data = try PimVault.encoder().encode(account)
        #expect(try PimVault.decoder().decode(MailAccount.self, from: data) == account)
    }

    @Test func mailAccountRoundTripsBrowserAuthMetadata() throws {
        let account = MailAccount(name: "google", host: "imap.gmail.com", username: "me", passwordCommand: "", provider: .google,
                                  auth: .init(
                                      browserProfile: BrowserProfile(id: "profile-1", name: "Google"),
                                      browserSession: BrowserSession(id: "session-1", profileID: "profile-1"),
                                      authState: .authenticated
                                  ))
        let data = try PimVault.encoder().encode(account)
        #expect(try PimVault.decoder().decode(MailAccount.self, from: data) == account)
    }
    @Test func emptyVaultLoadsEmptyCollections() throws {
        let vault = try tempVault()
        #expect(try vault.loadEvents().isEmpty)
        #expect(try vault.loadTodos().isEmpty)
        #expect(try vault.loadMailMessages().isEmpty)
    }

    @Test func roundTripsAllCollections() throws {
        let vault = try tempVault()
        // ISO8601 저장은 서브초를 버리므로 초 단위 고정 날짜로 라운드트립을 검증한다.
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let event = CalendarEvent(title: "회의", start: t0)
        let todo = TodoItem(title: "보고서", due: t0.addingTimeInterval(3600), links: [PimLink(kind: .event, id: event.id)], timeline: .init(createdAt: t0))
        let contact = Contact(name: "홍길동", emails: ["hong@example.com"])
        let note = Note(title: "메모", body: "# 본문", createdAt: t0, updatedAt: t0)
        let account = MailAccount(name: "work", host: "imap.example.com", username: "me", passwordCommand: "echo pw")
        let mail = MailMessage(box: .inbox, source: .init(account: "work", imapUID: 7), from: "a@b.c", subject: "hi", date: t0)

        try vault.saveEvents([event])
        try vault.saveTodos([todo])
        try vault.saveContacts([contact])
        try vault.saveNotes([note])
        try vault.saveMailAccounts([account])
        try vault.saveMailMessages([mail])

        #expect(try vault.loadEvents() == [event])
        #expect(try vault.loadTodos() == [todo])
        #expect(try vault.loadContacts() == [contact])
        #expect(try vault.loadNotes() == [note])
        #expect(try vault.loadMailAccounts() == [account])
        #expect(try vault.loadMailMessages() == [mail])
    }

    @Test func standardVaultHonorsEnvOverride() {
        let vault = PimVault.standard(environment: ["PIM_VAULT_ROOT": "/tmp/custom-vault"])
        #expect(vault.root.path == "/tmp/custom-vault")

        let fleetVault = PimVault.standard(environment: ["SWIFT_APP_STATE_ROOT": "/tmp/fleet-state-root"])
        #expect(fleetVault.root.path == "/tmp/fleet-state-root/PimVault")

        let testRunnerVault = PimVault.standard(environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"])
        #expect(testRunnerVault.root.path.contains("swift-app-state-root-tests/PimVault"))

        let fallback = PimVault.standard(environment: [:])
        #expect(fallback.root.lastPathComponent == "PimVault")
    }

    @Test func idPrefixMatching() throws {
        let a = TodoItem(id: "abc123", title: "a")
        let b = TodoItem(id: "abd999", title: "b")
        #expect(try PimVault.match([a, b], idPrefix: "abc")?.id == "abc123")
        #expect(try PimVault.match([a, b], idPrefix: "abd999")?.id == "abd999")
        #expect(try PimVault.match([a, b], idPrefix: "zzz") == nil)
        #expect(throws: PimVaultError.ambiguousID(prefix: "ab", count: 2)) {
            try PimVault.match([a, b], idPrefix: "ab")
        }
    }
}

@Suite struct PimLinkTests {
    @Test func tokenRoundTrip() {
        let link = PimLink(kind: .mail, id: "XYZ")
        #expect(link.token == "mail:XYZ")
        #expect(PimLink(token: "mail:XYZ") == link)
        #expect(PimLink(token: "bogus:1") == nil)
        #expect(PimLink(token: "mail:") == nil)
        #expect(PimLink(token: "no-colon") == nil)
    }
}

@Suite struct AgendaTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test func dayAggregation() {
        let today = date(2026, 7, 14, 9)
        let events = [
            CalendarEvent(title: "오늘 회의", start: date(2026, 7, 14, 10)),
            CalendarEvent(title: "내일 회의", start: date(2026, 7, 15, 10)),
            CalendarEvent(title: "기간 워크숍", start: date(2026, 7, 13), end: date(2026, 7, 16)),
        ]
        let todos = [
            TodoItem(title: "오늘 마감", due: date(2026, 7, 14, 18)),
            TodoItem(title: "지난 마감", due: date(2026, 7, 10)),
            TodoItem(title: "먼 마감", due: date(2026, 8, 1)),
            TodoItem(title: "마감 없음"),
            TodoItem(title: "끝난 일", due: date(2026, 7, 14), done: true),
        ]
        let mail = [
            MailMessage(box: .inbox, from: "a", subject: "unread"),
            MailMessage(box: .inbox, from: "b", subject: "read", content: .init(read: true)),
            MailMessage(box: .draft, from: "me", subject: "draft"),
        ]

        let agenda = Agenda.day(on: today, events: events, todos: todos, mail: mail, calendar: cal)
        #expect(agenda.events.map(\.title) == ["기간 워크숍", "오늘 회의"])
        #expect(agenda.dueTodos.map(\.title) == ["지난 마감", "오늘 마감"])
        #expect(agenda.openTodosWithoutDue == 1)
        #expect(agenda.unreadMailCount == 1)
    }

    @Test func upcomingReminders() {
        let now = date(2026, 7, 14, 9)
        let events = [
            CalendarEvent(title: "30분 뒤", start: date(2026, 7, 14, 9, 30)),
            CalendarEvent(title: "지난 것", start: date(2026, 7, 14, 8)),
            CalendarEvent(title: "너무 먼 것", start: date(2026, 7, 14, 12)),
        ]
        let todos = [
            TodoItem(title: "곧 마감", due: date(2026, 7, 14, 9, 15)),
            TodoItem(title: "끝난 일", due: date(2026, 7, 14, 9, 20), done: true),
        ]
        let reminders = Agenda.upcomingReminders(now: now, within: 3600, events: events, todos: todos)
        #expect(reminders.map(\.title) == ["곧 마감", "30분 뒤"])
    }
}

@Suite struct PimCLITests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    @Test func parsesAbsoluteAndRelativeDates() {
        let now = cal.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 9))!
        #expect(PimCLI.parseDate("2026-07-15", now: now, calendar: cal) != nil)
        #expect(PimCLI.parseDate("2026-07-15 14:30", now: now, calendar: cal) != nil)
        #expect(PimCLI.parseDate("today", now: now, calendar: cal) == cal.startOfDay(for: now))
        #expect(PimCLI.parseDate("+3d", now: now, calendar: cal) == cal.date(byAdding: .day, value: 3, to: now))
        #expect(PimCLI.parseDate("+30m", now: now, calendar: cal) == cal.date(byAdding: .minute, value: 30, to: now))
        #expect(PimCLI.parseDate("nonsense", now: now, calendar: cal) == nil)
    }
}
