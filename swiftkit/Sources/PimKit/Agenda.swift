import Foundation

/// 통합 agenda — 같은 vault 의 이벤트·투두·메일을 하루 화면 하나로 집계한다.
/// pim-agenda CLI/앱과 알림 데몬이 소비한다. 순수 함수라 테스트가 시계를 주입한다.
public struct AgendaDay: Codable, Equatable, Sendable {
    public struct Reminder: Codable, Equatable, Sendable {
        public enum Source: String, Codable, Sendable {
            case event, todo
        }

        public let source: Source
        public let id: String
        public let title: String
        /// 알림 기준 시각(이벤트 start / 투두 due).
        public let at: Date

        public init(source: Source, id: String, title: String, at: Date) {
            self.source = source
            self.id = id
            self.title = title
            self.at = at
        }
    }

    public let date: Date
    public let events: [CalendarEvent]
    /// 미완료 + (당일 마감 또는 이미 지난 마감).
    public let dueTodos: [TodoItem]
    /// 마감 없는 미완료는 별도 — 화면에서 접어 보여준다.
    public let openTodosWithoutDue: Int
    public let unreadMailCount: Int

    public init(
        date: Date,
        events: [CalendarEvent],
        dueTodos: [TodoItem],
        openTodosWithoutDue: Int,
        unreadMailCount: Int
    ) {
        self.date = date
        self.events = events
        self.dueTodos = dueTodos
        self.openTodosWithoutDue = openTodosWithoutDue
        self.unreadMailCount = unreadMailCount
    }
}

public enum Agenda {
    /// 특정 날짜의 agenda 집계.
    public static func day(
        on date: Date,
        events: [CalendarEvent],
        todos: [TodoItem],
        mail: [MailMessage],
        calendar: Calendar = .current
    ) -> AgendaDay {
        let dayEvents = events
            .filter { event in
                // 종일/기간 이벤트: [start, end] 가 해당 날짜와 겹치면 포함.
                let end = event.end ?? event.start
                let dayStart = calendar.startOfDay(for: date)
                guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
                return event.start < dayEnd && end >= dayStart
            }
            .sorted { $0.start < $1.start }

        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let open = todos.filter { !$0.done }
        let due = open
            .filter { todo in
                guard let due = todo.due else { return false }
                return due < endOfDay
            }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }

        let unread = mail.filter { $0.box == .inbox && !$0.read }.count

        return AgendaDay(
            date: date,
            events: dayEvents,
            dueTodos: due,
            openTodosWithoutDue: open.filter { $0.due == nil }.count,
            unreadMailCount: unread
        )
    }

    /// 알림 데몬용: `now` 로부터 `within` 안에 시작/마감하는 항목.
    /// 데몬은 마지막 발송 시각을 상태파일에 두고 재발송을 막는다.
    public static func upcomingReminders(
        now: Date,
        within: TimeInterval,
        events: [CalendarEvent],
        todos: [TodoItem]
    ) -> [AgendaDay.Reminder] {
        let horizon = now.addingTimeInterval(within)
        var reminders: [AgendaDay.Reminder] = []
        for event in events where event.start >= now && event.start <= horizon {
            reminders.append(.init(source: .event, id: event.id, title: event.title, at: event.start))
        }
        for todo in todos where !todo.done {
            if let due = todo.due, due >= now, due <= horizon {
                reminders.append(.init(source: .todo, id: todo.id, title: todo.title, at: due))
            }
        }
        return reminders.sorted { $0.at < $1.at }
    }
}
