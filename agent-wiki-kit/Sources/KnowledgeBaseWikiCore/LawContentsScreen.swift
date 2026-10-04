import Foundation
import WikiLedgerKit

// 목차 화면(ledger 3 원장의 첫 화면) 표시 모델 — 저장하지 않는 보기.
// 맨 위 "판단할 일"(대법원 대기·이의 기간 중인 개정안과 남은 시간·열린 드리밍 경보·자동 드리밍 정지),
// 그 아래 현행 목차(현행 `contents` 기록의 줄, 없으면 `contents` 명령과 같은 계산 + "계산한 목차(드리밍 전)"),
// 요약(현행 지식 기록 수·판단 대기 수·감사 위반 수 — 판단 대기는 위반이 아니다).
// 원천: 사건 목록 `LawCourtDocket.notices(now:)`, 드리밍 표시 `LawDreamMarks`·`LawDreamPause`, 목차 `LawContents`, 감사 `LawStore.audit`.
// 근거: docs/business-rules.md "드리밍"(목차)·"심급제"(대법원 공지·이의 기간)·"사실인정과 4종류"(판단 대기는 위반 아님).

/// 맨 위 "판단할 일".
public struct LawPendingDecisions: Sendable, Equatable {
    /// 이의 기간 중인 개정안 하나와 그 기간.
    public struct ObjectionWindow: Sendable, Equatable {
        public let proposal: LawCourtCase
        public let endsAt: Date
        /// 남은 시간(초). 0 이상.
        public let remaining: TimeInterval
    }

    /// 대법원 대기 건(공지 순). 결정 가능 시각은 `decidableAt`.
    public let supreme: [LawCourtCase]
    public let objections: [ObjectionWindow]
    /// 이 원장의 열린 드리밍 경보(마지막 드리밍 보고의 경보).
    public let alerts: [String]
    /// 자동 드리밍 정지 여부(모든 드리밍 원장 기준, 원장 기록에서 계산).
    public let dreamingPaused: Bool
    /// 정지시킨, 사람이 아직 확인하지 않은 원상회복 기록 id.
    public let pausedBy: [String]

    public var isEmpty: Bool { supreme.isEmpty && objections.isEmpty && alerts.isEmpty && !dreamingPaused }

    public init(notices: LawCourtNotices, objectionPeriod: TimeInterval, alerts: [String], pause: LawDreamPause, now: Date) {
        supreme = notices.supreme
        objections = notices.proposalsInObjection.map { item in
            let ends = item.noticedAt.addingTimeInterval(objectionPeriod)
            return ObjectionWindow(proposal: item, endsAt: ends, remaining: max(0, ends.timeIntervalSince(now)))
        }
        self.alerts = alerts
        dreamingPaused = pause.isPaused
        pausedBy = pause.unacknowledgedRestores
    }
}

/// 원장 요약 수.
public struct LawLedgerSummary: Sendable, Equatable {
    /// 현행 지식 기록(record·article·judgment) 수.
    public let knowledgeInForce: Int
    /// 사실인정이 없는 현행 지식 기록 수 — "판단 대기"(위반 아님).
    public let pendingJudgment: Int
    /// 감사 위반 수(판단 대기·가림·갈라진 현행은 넣지 않는다).
    public let violations: Int

    public init(knowledgeInForce: Int, pendingJudgment: Int, violations: Int) {
        self.knowledgeInForce = knowledgeInForce
        self.pendingJudgment = pendingJudgment
        self.violations = violations
    }

    public init(records: [LawStoredRecord], audit: LawAuditReport) {
        let view = LawLedgerView(records: records)
        knowledgeInForce = view.inForce.filter { LawRecordType.isKnowledge($0.record.type) }.count
        pendingJudgment = audit.pendingJudgment.count
        violations = audit.violations.count
    }
}

/// 목차 한 줄. 기록을 가리키는 줄이면 id 앞 8자리와(찾았으면) 그 기록 id.
public struct LawContentsLine: Sendable, Equatable, Identifiable {
    public let index: Int
    public let text: String
    public let idPrefix: String?
    public let recordID: String?

    public var id: Int { index }
}

public struct LawContentsScreen: Sendable {
    public let worldName: String
    public let pending: LawPendingDecisions
    public let lines: [LawContentsLine]
    /// 현행 목차 기록이 없어 `contents` 명령과 같은 계산으로 만든 목차인가("계산한 목차(드리밍 전)").
    public let isComputed: Bool
    /// 현행 목차 기록 id(계산한 목차면 nil).
    public let contentsRecordID: String?
    public let contentsPromulgated: Date?
    public let summary: LawLedgerSummary
    /// 기록이 하나도 없는 원장.
    public let isEmptyLedger: Bool
    let records: [LawStoredRecord]

    /// 목차 줄의 id 앞자리로 이 원장의 기록을 찾는다(`resolve(prefix:in:)`).
    public func recordID(forPrefix prefix: String) -> String? {
        Self.resolve(prefix: prefix, in: records)
    }

    /// id 앞자리 → 기록 id. 현행 기록 중 하나만 맞으면 그것, 아니면 전체 중 하나만 맞을 때 그것. 4자 미만·여럿이면 nil.
    public static func resolve(prefix: String, in records: [LawStoredRecord]) -> String? {
        let key = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        guard key.count >= 4 else { return nil }
        let matches = records.filter { $0.id.hasPrefix(key) }
        guard !matches.isEmpty else { return nil }
        if matches.count == 1 { return matches[0].id }
        let view = LawLedgerView(records: records)
        let current = matches.filter { view.isInForce($0.id) }
        return current.count == 1 ? current[0].id : nil
    }

    /// 목차 줄에서 기록을 가리키는 id 앞 8자리 — 기록 줄(`<8자> …`)과 공지 줄(`대법원 공지: <8자> …`·`이의 기간 개정안: <8자> …`).
    public static func idPrefix(ofLine line: String) -> String? {
        var rest = Substring(line)
        for notice in noticePrefixes where rest.hasPrefix(notice) {
            rest = rest.dropFirst(notice.count)
            break
        }
        guard let token = rest.split(separator: " ", maxSplits: 1).first, token.count == 8,
              token.allSatisfy({ $0.isHexDigit && !$0.isUppercase })
        else { return nil }
        return String(token)
    }

    static let noticePrefixes = ["대법원 공지: ", "이의 기간 개정안: "]

    // MARK: - 만들기

    /// 기록과 원천에서 만든다(파일을 읽지 않는다 — 시험과 배경 읽기가 같은 계산을 쓴다).
    public static func make(
        worldName: String, records: [LawStoredRecord], notices: LawCourtNotices, objectionPeriod: TimeInterval,
        pause: LawDreamPause, audit: LawAuditReport, maxLines: Int, now: Date
    ) -> LawContentsScreen {
        let alerts = LawDreamMarks(records: records).openAlerts
        let current = LawContents.current(in: records)
        let texts: [String]
        if let current {
            texts = current.record.body.split(separator: "\n").map(String.init)
        } else {
            texts = LawContents.lines(
                records: records, notices: notices, alerts: alerts, maxLines: maxLines, objectionPeriod: objectionPeriod)
        }
        let lines = texts.enumerated().map { index, text in
            let prefix = idPrefix(ofLine: text)
            return LawContentsLine(
                index: index, text: text, idPrefix: prefix, recordID: prefix.flatMap { resolve(prefix: $0, in: records) })
        }
        return LawContentsScreen(
            worldName: worldName,
            pending: LawPendingDecisions(
                notices: notices, objectionPeriod: objectionPeriod, alerts: alerts, pause: pause, now: now),
            lines: lines, isComputed: current == nil, contentsRecordID: current?.id,
            contentsPromulgated: current?.record.promulgated,
            summary: LawLedgerSummary(records: records, audit: audit), isEmptyLedger: records.isEmpty, records: records)
    }

    /// 원장 하나를 읽어 만든다. 화면은 배경에서 부른다(원장 폴더를 훑는다).
    public static func load(target: LawLedgerTarget, now: Date = Date()) -> LawContentsScreen {
        let records = target.store.scan()
        let court = target.file?.court ?? LawCourtSettings()
        let docket = LawCourtDocket(records: records, objectionPeriod: court.objectionPeriod)
        let file = target.file ?? BoundLedgerFile(worlds: target.catalog.worlds)
        let pause = LawDreamPause.evaluate(LawDreamService.targets(file: file, catalog: target.catalog).map {
            $0.worldName == target.worldName ? records : $0.store.scan()
        })
        let maxLines = (file.dream ?? LawDreamSettings()).resolvedContentsMaxLines
        return make(
            worldName: target.worldName, records: records, notices: docket.notices(now: now),
            objectionPeriod: court.objectionPeriod, pause: pause, audit: LawScreenAudit.audit(target),
            maxLines: maxLines, now: now)
    }
}

/// 화면 요약용 감사 — 공포 경로와 같은 범위 해석기(같은 원장·상위·전신)와 승격본 확인자로 본다.
enum LawScreenAudit {
    static func audit(_ target: LawLedgerTarget) -> LawAuditReport {
        let index = LawScopeIndex(current: target.worldName, catalog: target.catalog)
        return target.store.audit(context: LawEnactContext(
            resolver: LawScopeReferenceResolver(index: index), promotions: LawPromotionWitness(index: index)))
    }
}
