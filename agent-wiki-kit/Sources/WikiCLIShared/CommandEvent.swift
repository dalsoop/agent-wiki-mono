import Foundation
import KnowledgeBaseWikiCore

/// 사건층 조종 — append-only 사건 로그(events/*.ndjson). 사실·운영 기록 전용.
/// 뎁스 3층: run(작업)>step(단계)>detail(세부). 판단(해석)은 md 객체로 발행한다.
private func eventTree(_ log: EventLog, arguments: [String]) {
    let n = arguments.count >= 3 ? (Int(arguments[2]) ?? 30) : 30
    let all = log.all()
    let starts = all.filter { $0.level == .run && $0.outcome == .pending }
    let closed = Dictionary(grouping: all.filter { $0.level == .run && $0.outcome != .pending && $0.parent != nil },
                            by: { $0.parent! })
    let recent = starts.suffix(n)
    if recent.isEmpty { print("(작업 사건 없음)") } // allow:debug
    for run in recent {
        let end = closed[run.id]?.first
        let mark = end.map { $0.outcome == .ok ? "✓" : "✗" } ?? "…"
        let kids = log.children(of: run.id, in: all).filter { $0.level == .step }
        print("\(mark) \(iso(run.occurred))  \(run.rel)  \(short(run.subject))  (\(run.writer))  단계 \(kids.count)") // allow:debug
        for k in kids.prefix(8) {
            let src = k.source.map { "  src:\($0.prefix(10))" } ?? ""
            print("    ├ \(k.rel) \(short(k.object ?? k.subject))\(src)") // allow:debug
        }
    }
}

private func eventComplete(
    _ log: EventLog, sub: String, arguments: [String],
    author: String, occurred: Date, attrs: [String: String]
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
    let event = Event(
        writer: author, subject: start.subject,
        rel: sub == "ok" ? "성공" : "실패", occurred: occurred,
        level: .run,
        extras: Event.Extras(parent: runID, outcome: sub == "ok" ? .ok : .fail, attrs: attrs))
    do { try log.append(event); print(event.id) } // allow:debug
    catch { fail("event 기록 실패: \(error)") }
}

private func eventOpt(_ name: String, in arguments: [String]) -> String? {
    guard let i = arguments.firstIndex(of: name), arguments.count > i + 1 else { return nil }
    return arguments[i + 1]
}

private func eventAttrs(_ arguments: [String]) -> [String: String] {
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

private func eventOccurred(_ arguments: [String]) -> Date {
    if let raw = eventOpt("--occurred", in: arguments),
       let d = ISO8601DateFormatter().date(from: raw) { return d }
    return Date()
}

private func emitEvent(_ event: Event, to log: EventLog) {
    do { try log.append(event); print(event.id) } // allow:debug
    catch { fail("event 기록 실패: \(error)") }
}

public func runEvent(root: URL, author: String, arguments: [String]) {
    let log = EventLog(root: root)
    let sub = arguments.count >= 2 ? arguments[1] : "tree"

    switch sub {
    case "start":
        guard let subject = eventOpt("--subject", in: arguments),
              let rel = eventOpt("--rel", in: arguments) else {
            fail("event start --subject <> --rel <> [--source <sha>] [--attr k=v]...")
        }
        emitEvent(Event(
            writer: author, subject: subject, rel: rel,
            occurred: eventOccurred(arguments), level: .run,
            extras: Event.Extras(source: eventOpt("--source", in: arguments), outcome: .pending, attrs: eventAttrs(arguments))), to: log)

    case "step", "detail":
        guard let subject = eventOpt("--subject", in: arguments),
              let rel = eventOpt("--rel", in: arguments) else {
            fail("event \(sub) --subject <> --rel <> --parent <run-id> [--source <sha>] [--object <>] [--attr k=v]...")
        }
        emitEvent(Event(
            writer: author, subject: subject, rel: rel,
            occurred: eventOccurred(arguments), level: sub == "step" ? .step : .detail,
            extras: Event.Extras(
                object: eventOpt("--object", in: arguments), source: eventOpt("--source", in: arguments),
                parent: eventOpt("--parent", in: arguments), attrs: eventAttrs(arguments))), to: log)

    case "ok", "fail":
        eventComplete(log, sub: sub, arguments: arguments, author: author,
                      occurred: eventOccurred(arguments), attrs: eventAttrs(arguments))

    case "append":
        guard let subject = eventOpt("--subject", in: arguments),
              let rel = eventOpt("--rel", in: arguments) else {
            fail("event append --subject <> --rel <> [--object <>] [--source <sha>] [--level run|step|detail] [--parent <id>] [--attr k=v]...")
        }
        let level = Event.Level(rawValue: eventOpt("--level", in: arguments) ?? "step") ?? .step
        emitEvent(Event(
            writer: author, subject: subject, rel: rel,
            occurred: eventOccurred(arguments), level: level,
            extras: Event.Extras(
                object: eventOpt("--object", in: arguments), source: eventOpt("--source", in: arguments),
                parent: eventOpt("--parent", in: arguments), attrs: eventAttrs(arguments))), to: log)

    case "tree":
        eventTree(log, arguments: arguments)

    case "tail":
        let n = arguments.count >= 3 ? (Int(arguments[2]) ?? 20) : 20
        for e in log.tail(n) { print("\(iso(e.occurred))  [\(e.level.rawValue)] \(e.subject) —[\(e.rel)]→ \(e.object ?? "·")  (\(e.writer))") } // allow:debug

    case "count":
        let all = log.all()
        let starts = all.filter { $0.level == .run && $0.outcome == .pending }.count
        print("사건 \(all.count)개 (작업 \(starts) · 세그먼트 \(log.segments().count))") // allow:debug

    default:
        fail(usage)
    }
}

private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
private func short(_ id: String) -> String {
    id.count > 12 && id.contains("-") ? String(id.prefix(8)) : id
}
