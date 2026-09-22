import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// 사건층 조종 — append-only 사건 로그(events/*.ndjson). 사실·운영 기록 전용.
/// 뎁스 3층: run(작업)>step(단계)>detail(세부). 판단(해석)은 md 객체로 발행한다.
func runEvent(root: URL, author: String, arguments: [String]) {
    let log = EventLog(root: root)
    let sub = arguments.count >= 2 ? arguments[1] : "tree"

    func opt(_ name: String) -> String? {
        guard let i = arguments.firstIndex(of: name), arguments.count > i + 1 else { return nil }
        return arguments[i + 1]
    }
    func attrs() -> [String: String] {
        var out: [String: String] = [:]
        var idx = 2
        while idx < arguments.count {
            if arguments[idx] == "--attr", idx + 1 < arguments.count {
                let kv = arguments[idx + 1].split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2 { out[kv[0]] = kv[1] }
                idx += 2
            } else { idx += 1 }
        }
        return out
    }
    func occurred() -> Date {
        if let raw = opt("--occurred"), let d = ISO8601DateFormatter().date(from: raw) { return d }
        return Date()
    }
    func emit(_ event: Event) {
        do { try log.append(event); print(event.id) }
        catch { fail("event 기록 실패: \(error)") }
    }

    switch sub {
    case "start":
        eventStart(author: author, opt: opt, attrs: attrs, occurred: occurred, emit: emit)
    case "step", "detail":
        eventStep(sub: sub, author: author, opt: opt, attrs: attrs, occurred: occurred, emit: emit)
    case "ok", "fail":
        eventClose(sub: sub, arguments: arguments, log: log, author: author, attrs: attrs, occurred: occurred, emit: emit)
    case "append":
        eventAppend(author: author, opt: opt, attrs: attrs, occurred: occurred, emit: emit)
    case "tree":
        eventTree(arguments: arguments, log: log)
    case "tail":
        let n = arguments.count >= 3 ? (Int(arguments[2]) ?? 20) : 20
        for e in log.tail(n) {
            print("\(iso(e.occurred))  [\(e.level.rawValue)] \(e.subject) —[\(e.rel)]→ \(e.object ?? "·")  (\(e.writer))")
        }
    case "count":
        let all = log.all()
        let starts = all.filter { $0.level == .run && $0.outcome == .pending }.count
        print(CLILocalization.text("CommandEvent.print", values: all.count, starts, log.segments().count))
    default:
        fail(usage)
    }
}

private func eventStart(
    author: String,
    opt: (String) -> String?,
    attrs: () -> [String: String],
    occurred: () -> Date,
    emit: (Event) -> Void
) {
    guard let subject = opt("--subject"), let rel = opt("--rel") else {
        fail("event start --subject <> --rel <> [--source <sha>] [--attr k=v]...")
    }
    emit(Event(
        writer: author,
        subject: subject,
        rel: rel,
        occurred: occurred(),
        level: .run,
        extras: Event.Extras(source: opt("--source"), outcome: .pending, attrs: attrs())
    ))
}

private func eventStep(
    sub: String,
    author: String,
    opt: (String) -> String?,
    attrs: () -> [String: String],
    occurred: () -> Date,
    emit: (Event) -> Void
) {
    guard let subject = opt("--subject"), let rel = opt("--rel") else {
        fail("event \(sub) --subject <> --rel <> --parent <run-id> [--source <sha>] [--object <>] [--attr k=v]...")
    }
    emit(Event(
        writer: author,
        subject: subject,
        rel: rel,
        occurred: occurred(),
        level: sub == "step" ? .step : .detail,
        extras: Event.Extras(
            object: opt("--object"),
            source: opt("--source"),
            parent: opt("--parent"),
            attrs: attrs()
        )
    ))
}

private func eventClose(
    sub: String,
    arguments: [String],
    log: EventLog,
    author: String,
    attrs: () -> [String: String],
    occurred: () -> Date,
    emit: (Event) -> Void
) {
    guard arguments.count >= 3 else { fail("event \(sub) <run-id> [--attr k=v]...") }
    let runID = arguments[2]
    let all = log.all()
    guard let start = all.first(where: { $0.id == runID }), start.level == .run else {
        fail("event \(sub): 없거나 작업(run)이 아닌 run-id: \(runID)")
    }
    if all.contains(where: { $0.parent == runID && $0.level == .run && $0.outcome != .pending }) {
        fail("event \(sub): 이미 닫힌 작업입니다: \(runID)")
    }
    emit(Event(
        writer: author,
        subject: start.subject,
        rel: sub == "ok" ? "성공" : "실패",
        occurred: occurred(),
        level: .run,
        extras: Event.Extras(
            parent: runID,
            outcome: sub == "ok" ? .ok : .fail,
            attrs: attrs()
        )
    ))
}

private func eventAppend(
    author: String,
    opt: (String) -> String?,
    attrs: () -> [String: String],
    occurred: () -> Date,
    emit: (Event) -> Void
) {
    guard let subject = opt("--subject"), let rel = opt("--rel") else {
        fail("event append --subject <> --rel <> [--object <>] [--source <sha>] [--level run|step|detail] [--parent <id>] [--attr k=v]...")
    }
    let level = Event.Level(rawValue: opt("--level") ?? "step") ?? .step
    emit(Event(
        writer: author,
        subject: subject,
        rel: rel,
        occurred: occurred(),
        level: level,
        extras: Event.Extras(
            object: opt("--object"),
            source: opt("--source"),
            parent: opt("--parent"),
            attrs: attrs()
        )
    ))
}

private func eventTree(arguments: [String], log: EventLog) {
    let n = arguments.count >= 3 ? (Int(arguments[2]) ?? 30) : 30
    let all = log.all()
    let starts = all.filter { $0.level == .run && $0.outcome == .pending }
    let closed = Dictionary(
        grouping: all.filter { $0.level == .run && $0.outcome != .pending && $0.parent != nil },
        by: { $0.parent! }
    )
    let recent = starts.suffix(n)
    if recent.isEmpty { print(CLILocalization.string("CommandEvent.print-2")) }
    for run in recent {
        let end = closed[run.id]?.first
        let mark = end.map { $0.outcome == .ok ? "✓" : "✗" } ?? "…"
        let kids = log.children(of: run.id, in: all).filter { $0.level == .step }
        print(CLILocalization.format("CommandEvent.print-3", mark, iso(run.occurred), run.rel, short(run.subject), run.writer, kids.count))
        for k in kids.prefix(8) {
            let src = k.source.map { "  src:\($0.prefix(10))" } ?? ""
            print("    ├ \(k.rel) \(short(k.object ?? k.subject))\(src)")
        }
    }
}

private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
private func short(_ id: String) -> String {
    id.count > 12 && id.contains("-") ? String(id.prefix(8)) : id
}
