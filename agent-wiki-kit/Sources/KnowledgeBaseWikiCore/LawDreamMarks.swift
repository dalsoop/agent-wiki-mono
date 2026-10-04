import Foundation
import WikiLedgerKit

// 드리밍이 원장에 남긴 표시 — 드리밍 보고(묶음 id·경보)와 사람의 재개 기록 — 에서 계산하는 보기. 저장하지 않는다.
// 정지 여부도 원장에서 계산한다: 드리밍 묶음을 대상으로 한 원상회복 기록이 있고 그 기록을 사람이 재개(`dream resume`)로
// 확인하지 않았으면 자동 드리밍이 정지된 상태다. 원장은 git 으로 모든 기기에 퍼지므로 어느 기기의 원상회복·재개든 드리밍 기기가 본다.
// 근거: docs/business-rules.md "드리밍"(안전장치: 드리밍 묶음이 원상회복되면 누가 했든 자동 드리밍 정지, `dream resume` 은
// `author-kind: human` 만), "공포·개정·폐지·원상회복"(restore 는 개정이면 이전 판 재공포, 신규면 폐지).

/// 드리밍 보고·재개 기록의 표기(드리밍이 쓰고 드리밍이 읽는다).
public enum LawDreamRecordFormat {
    public static let appSlug = "agent-wiki"
    public static var appAuthor: String { "app:\(appSlug)" }
    public static let reportTitlePrefix = "드리밍 보고"
    public static let resumeTitle = "드리밍 재개"
    public static let batchPrefix = "batch: "
    public static let alertPrefix = "경보: "
    public static let restorePrefix = "restore: "
    public static let runPrefix = "run: "
    public static let ledgerPrefix = "ledger: "
    public static let triggerPrefix = "trigger: "
    /// 보고 본문의 절 머리 — 뒤에 `<수>건` 이 붙는 절은 `countedHeading` 으로 쓴다.
    public static let materialsHeading = "## 읽은 재료"
    public static let appliedHeading = "## 적용한 변경"
    public static let discardedHeading = "## 버린 제안"
    public static let deferredHeading = "## 미룬 제안"
    public static let alertsHeading = "## 경보"
    public static let migrationsHeading = "## 이관"
    public static let archiveHeading = "## 적재 보고"
    /// 목록 줄 앞머리(적용한 변경·버린 제안).
    public static let itemPrefix = "- "
    /// 버린 제안 줄의 제안과 이유 사이.
    public static let discardSeparator = ": "

    /// `<머리> <수>건`.
    public static func countedHeading(_ heading: String, _ count: Int) -> String { "\(heading) \(count)건" }

    public static func isDreamReport(_ record: LawRecord) -> Bool {
        record.type == LawRecordType.report.rawValue && record.author == appAuthor
            && (record.title ?? "").hasPrefix(reportTitlePrefix)
    }

    public static func isResume(_ record: LawRecord) -> Bool {
        record.type == LawRecordType.report.rawValue && record.authorKind == LawAuthorKind.human.rawValue
            && record.title == resumeTitle
    }

    static func values(_ body: String, prefix: String) -> [String] {
        body.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line in
            line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) : nil
        }.filter { !$0.isEmpty }
    }
}

/// 드리밍 보고 본문에서 읽은 것. 쓰는 쪽은 `LawDreamService.reportBody`, 형식 상수는 `LawDreamRecordFormat` 하나다.
public struct LawDreamReportSummary: Sendable, Equatable {
    public struct Discarded: Sendable, Equatable {
        public let proposal: String
        public let reason: String

        public init(proposal: String, reason: String) {
            self.proposal = proposal
            self.reason = reason
        }
    }

    public var batch: String?
    public var run: String?
    public var ledgerKey: String?
    public var trigger: String?
    /// 적용한 변경 수(절 머리의 수).
    public var appliedCount = 0
    /// 적용한 변경 줄(`<종류>[ <대상 8자>] → <id 8자 …>[ (<메모>)]`).
    public var applied: [String] = []
    public var discardedCount = 0
    public var discarded: [Discarded] = []
    public var deferredCount = 0
    public var alerts: [String] = []
    public var migrations = 0

    public init() {}

    /// 보고 본문을 읽는다. 모르는 줄은 건너뛴다(보고 형식이 늘어도 읽기가 깨지지 않게).
    public static func parse(_ body: String) -> LawDreamReportSummary {
        typealias F = LawDreamRecordFormat
        var summary = LawDreamReportSummary()
        var section: String?
        func count(_ line: String, heading: String) -> Int? {
            guard line.hasPrefix(heading + " "), line.hasSuffix("건") else { return nil }
            return Int(line.dropFirst(heading.count + 1).dropLast().trimmingCharacters(in: .whitespaces))
        }
        func value(_ line: String, _ prefix: String) -> String? {
            line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) : nil
        }
        for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("## ") {
                section = nil
                if let n = count(line, heading: F.appliedHeading) {
                    summary.appliedCount = n
                    section = F.appliedHeading
                } else if let n = count(line, heading: F.discardedHeading) {
                    summary.discardedCount = n
                    section = F.discardedHeading
                } else if let n = count(line, heading: F.deferredHeading) {
                    summary.deferredCount = n
                } else if count(line, heading: F.alertsHeading) != nil {
                    section = F.alertsHeading
                } else if let n = count(line, heading: F.migrationsHeading) {
                    summary.migrations = n
                }
                continue
            }
            if section == nil {
                if summary.batch == nil, let v = value(line, F.batchPrefix) { summary.batch = v; continue }
                if summary.run == nil, let v = value(line, F.runPrefix) { summary.run = v; continue }
                if summary.ledgerKey == nil, let v = value(line, F.ledgerPrefix) { summary.ledgerKey = v; continue }
                if summary.trigger == nil, let v = value(line, F.triggerPrefix) { summary.trigger = v; continue }
                continue
            }
            switch section {
            case F.appliedHeading?:
                if let item = value(line, F.itemPrefix) { summary.applied.append(item) }
            case F.discardedHeading?:
                guard let item = value(line, F.itemPrefix) else { continue }
                if let range = item.range(of: F.discardSeparator) {
                    summary.discarded.append(Discarded(
                        proposal: String(item[..<range.lowerBound]), reason: String(item[range.upperBound...])))
                } else {
                    summary.discarded.append(Discarded(proposal: item, reason: ""))
                }
            case F.alertsHeading?:
                if let alert = value(line, F.alertPrefix), !alert.isEmpty { summary.alerts.append(alert) }
            default: break
            }
        }
        return summary
    }
}

/// 원장 하나의 드리밍 표시.
public struct LawDreamMarks: Sendable {
    public let records: [LawStoredRecord]

    public init(records: [LawStoredRecord]) { self.records = records }

    public var reports: [LawStoredRecord] { records.filter { LawDreamRecordFormat.isDreamReport($0.record) } }

    /// 드리밍이 공포한 묶음 id(보고에 적힌 것).
    public var dreamBatches: Set<String> {
        Set(reports.flatMap { LawDreamRecordFormat.values($0.record.body, prefix: LawDreamRecordFormat.batchPrefix) })
    }

    /// 열린 경보 — 이 원장의 마지막 드리밍 보고의 경보(다음 드리밍 보고가 대신한다).
    public var openAlerts: [String] {
        guard let last = reports.last else { return [] }
        return LawDreamRecordFormat.values(last.record.body, prefix: LawDreamRecordFormat.alertPrefix)
    }

    /// 사람이 재개로 확인한 원상회복 기록 id.
    public var acknowledgedRestores: Set<String> {
        Set(records.filter { LawDreamRecordFormat.isResume($0.record) }
            .flatMap { LawDreamRecordFormat.values($0.record.body, prefix: LawDreamRecordFormat.restorePrefix) })
    }

    /// 묶음들(`batches`)을 대상으로 한 원상회복 기록 id(공포 순).
    /// 감지 방법(`LawStore.restore` 의 표기와 같다):
    /// - 신규였던 기록의 원상회복 = 그 기록을 `repeals` 하고 본문이 `restore <묶음>` 인 기록.
    /// - 개정이었던 기록의 원상회복 = 그 기록을 `amends` 하고 제목·본문이 그 기록의 이전 판(`amends` 대상)과 같은 기록.
    /// 원상회복 기록 자신이 드리밍 묶음이면(드리밍이 스스로 되돌린 경우) 세지 않는다.
    public func restores(of batches: Set<String>) -> [String] {
        guard !batches.isEmpty else { return [] }
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var found: [String] = []
        for candidate in records {
            let record = candidate.record
            if let batch = record.batch, batches.contains(batch) { continue }
            if let repealed = record.repeals, let target = byID[repealed]?.record, let batch = target.batch,
               batches.contains(batch), record.body == "restore \(batch)" {
                found.append(candidate.id)
                continue
            }
            if let amended = record.amends, let target = byID[amended]?.record, let batch = target.batch,
               batches.contains(batch), let previousID = target.amends, let previous = byID[previousID]?.record,
               record.body == previous.body, record.title == previous.title {
                found.append(candidate.id)
            }
        }
        return found
    }
}

/// 여러 원장에 걸친 정지 판정.
public struct LawDreamPause: Sendable, Equatable {
    /// 사람이 아직 확인하지 않은 드리밍 묶음 원상회복 기록 id.
    public let unacknowledgedRestores: [String]

    public var isPaused: Bool { !unacknowledgedRestores.isEmpty }

    public init(unacknowledgedRestores: [String]) { self.unacknowledgedRestores = unacknowledgedRestores }

    /// 드리밍 원장들의 기록 묶음들에서 판정한다. 드리밍 묶음·재개 확인은 모든 원장의 것을 합쳐 본다.
    public static func evaluate(_ ledgers: [[LawStoredRecord]]) -> LawDreamPause {
        let marks = ledgers.map(LawDreamMarks.init(records:))
        let batches = marks.reduce(into: Set<String>()) { $0.formUnion($1.dreamBatches) }
        let acknowledged = marks.reduce(into: Set<String>()) { $0.formUnion($1.acknowledgedRestores) }
        let restores = marks.flatMap { $0.restores(of: batches) }
        return LawDreamPause(unacknowledgedRestores: restores.filter { !acknowledged.contains($0) })
    }
}
