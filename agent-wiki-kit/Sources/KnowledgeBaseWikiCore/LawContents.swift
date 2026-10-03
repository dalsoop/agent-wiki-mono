import Foundation
import WikiLedgerKit

// 목차(`contents`) — 원장마다 하나. 현행 기록을 가리키는 줄(id 앞 8자리 + 한 줄 설명)만 두고, 맨 위에 열린 경보·
// 대법원 공지·이의 제기 기간 중인 개정안을 둔다. 드리밍이 새 판(이전 목차의 개정)으로 공포하고, 세션 시작 훅이 보여 준다.
// 근거: docs/business-rules.md "드리밍"(목차: 줄당 150자·200줄 이내, 조정 가능)·"심급제"(대법원 공지·이의 기간),
// docs/contracts.md `contents`.

public enum LawContents {
    /// 줄당 글자 상한.
    public static let lineLimit = 150
    /// 목차 기록의 제목 접두어.
    public static let titlePrefix = "목차: "

    /// 목차에 싣는 현행 기록의 유형 순서(지식 기록 + 판결 등록).
    static let listedTypes: [LawRecordType] = [.article, .judgment, .registration, .record]

    /// 목차 줄들. 공지(경보·대법원·이의 기간 개정안) → 현행 기록(유형 순, 같은 유형은 새것 먼저).
    /// 전체가 `maxLines` 를 넘으면 마지막 줄에 남은 건수를 적는다.
    public static func lines(
        records: [LawStoredRecord], notices: LawCourtNotices, alerts: [String], maxLines: Int,
        objectionPeriod: TimeInterval
    ) -> [String] {
        let limit = max(1, maxLines)
        var head: [String] = alerts.map { "경보: \(oneLine($0))" }
        for item in notices.supreme {
            let when = item.decidableAt.map { " — 결정 가능 \(LawTime.format($0))" } ?? ""
            head.append("대법원 공지: \(item.id.prefix(8)) \(oneLine(item.title ?? ""))\(when)")
        }
        for item in notices.proposalsInObjection {
            let until = LawTime.format(item.noticedAt.addingTimeInterval(objectionPeriod))
            head.append("이의 기간 개정안: \(item.id.prefix(8)) \(oneLine(item.title ?? "")) — \(until) 까지")
        }
        head = head.map(clip)
        if head.count >= limit {
            let kept = Array(head.prefix(limit - 1))
            return kept + [clip("… 공지 \(head.count - kept.count)건 더")]
        }

        let view = LawLedgerView(records: records)
        let current = view.inForce
        var body: [String] = []
        for type in listedTypes {
            let rows = current.filter { $0.record.type == type.rawValue }
                .sorted { ($0.record.promulgated, $0.id) > ($1.record.promulgated, $1.id) }
            body += rows.map { line(for: $0, type: type) }
        }
        let room = limit - head.count
        guard body.count > room else { return head + body }
        let kept = Array(body.prefix(room - 1))
        return head + kept + [clip("… 외 \(body.count - kept.count)건 — agent-wiki list")]
    }

    static func line(for stored: LawStoredRecord, type: LawRecordType) -> String {
        let marker = type == .record ? "" : "[\(type.rawValue)] "
        return clip("\(stored.id.prefix(8)) \(marker)\(summary(of: stored.record))")
    }

    /// 한 줄 설명 — 제목, 없으면 본문의 첫 내용 줄.
    static func summary(of record: LawRecord) -> String {
        if let title = record.title, !oneLine(title).isEmpty { return oneLine(title) }
        let first = record.body.split(separator: "\n").map(String.init).first {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return oneLine(first ?? "")
    }

    /// 줄바꿈·연속 공백을 공백 하나로.
    public static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// 줄당 글자 상한으로 자른다.
    public static func clip(_ line: String) -> String {
        guard line.count > lineLimit else { return line }
        return String(line.prefix(lineLimit - 1)) + "…"
    }

    // MARK: - 원장

    /// 이 원장의 현행 목차 기록(가장 늦은 것).
    public static func current(in records: [LawStoredRecord]) -> LawStoredRecord? {
        let view = LawLedgerView(records: records)
        return records.filter { $0.record.type == LawRecordType.contents.rawValue && view.isInForce($0.id) }.last
    }

    /// 원장 하나의 목차 줄(그 원장의 열린 경보 = 마지막 드리밍 보고의 경보).
    public static func lines(for target: LawLedgerTarget, maxLines: Int, now: Date = Date()) -> [String] {
        let records = target.store.scan()
        let settings = target.file?.court ?? LawCourtSettings()
        let docket = LawCourtDocket(records: records, objectionPeriod: settings.objectionPeriod)
        return lines(
            records: records, notices: docket.notices(now: now), alerts: LawDreamMarks(records: records).openAlerts,
            maxLines: maxLines, objectionPeriod: settings.objectionPeriod)
    }

    /// 목차 본문(줄마다 한 줄).
    public static func body(_ lines: [String]) -> String {
        (lines.isEmpty ? ["(현행 기록 없음)"] : lines).joined(separator: "\n") + "\n"
    }

    /// 새 판 공포 — 현행 목차와 본문이 같으면 공포하지 않는다(nil). 있으면 그것을 개정한다.
    @discardableResult
    public static func publish(
        lines: [String], target: LawLedgerTarget, actor: LawActor, now: Date = Date()
    ) throws -> LawStoredRecord? {
        let text = body(lines)
        let previous = current(in: target.store.scan())
        if let previous, previous.record.body == text { return nil }
        let draft = LawDraft(
            actor: actor, title: titlePrefix + target.worldName, type: LawRecordType.contents.rawValue,
            origin: LawOrigin.dream.rawValue, amends: previous?.id, body: text)
        return try LawEnactService.enact(draft, target: target, now: now)
    }
}

// MARK: - 세션 시작

extension LawContents {
    /// 세션 시작 훅이 보여 줄 원장 — 세션의 테넌트 원장(대응표에 있으면)과 공유 원장(상위 없는 ledger 3 원장).
    public static func sessionLedgers(tenant: String?, file: BoundLedgerFile, catalog: WorldBindingCatalog) -> [String] {
        func usable(_ name: String) -> Bool {
            catalog.isLedgerThree(name) && catalog.world(named: name)?.key != nil && !catalog.isArchived(name)
        }
        var names: [String] = []
        if let world = TenantLedgerRouting.resolve(tenant: tenant, file: file).worldName, usable(world) {
            names.append(world)
            if let shared = catalog.ancestorNames(of: world).last(where: usable), !names.contains(shared) {
                names.append(shared)
            }
        }
        if !names.contains(where: { catalog.parentName(of: $0) == nil }),
           let shared = catalog.worlds.first(where: { $0.parent == nil && usable($0.name) })?.name {
            names.append(shared)
        }
        return names
    }

    /// 세션 시작 훅의 표준 출력 — 각 원장의 현행 목차 기록 본문. 목차가 없는 원장은 건너뛴다.
    public static func sessionStartText(tenant: String?, file: BoundLedgerFile, catalog: WorldBindingCatalog) -> String {
        var blocks: [String] = []
        for name in sessionLedgers(tenant: tenant, file: file, catalog: catalog) {
            guard let path = catalog.world(named: name)?.rootPath,
                  let contents = current(in: LawStore(root: URL(fileURLWithPath: path)).scan())
            else { continue }
            blocks.append("# agent-law 목차 — \(name)\n" + contents.record.body)
        }
        return blocks.joined(separator: "\n")
    }
}
