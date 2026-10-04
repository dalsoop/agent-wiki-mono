import Foundation
import SessionKit
import WikiLedgerKit

// 심급제의 쓰기 — 이의(`appeal`)·개정안(`proposal`)·항소심(`hear`)·대법원(`decide`).
// 근거: docs/business-rules.md "심급제"·"관계"·"본문 머리 칸"·"작성자와 모델 기록"·"드리밍",
// docs/security.md agent-law 격리 표(대법원 결정은 사용자 발화 증언 필요, 작성자 무관),
// docs/contracts.md "agent-law 명령"(심급 행), 결정 0007.
// 모든 쓰기는 `LawEnactService`(쓰기 게이트·범위 해석기·후처리) 하나로 한다.

public enum LawCourtError: Error, Equatable, CustomStringConvertible {
    case targetNotFound(String)
    case supremeRulingIsFinal(String)
    case emptyReason
    case emptyScope
    case emptyContent
    case caseNotFound(String)
    case notPendingSupreme(String)
    case objectionPeriod(until: String)
    case testimonyNotFound(String)
    case testimonyNotUserEvidence(String)

    public var description: String {
        switch self {
        case .targetNotFound(let id): return "대상 기록을 찾을 수 없음(또는 허용 범위 밖): \(id)"
        case .supremeRulingIsFinal(let id): return "대법원 결정은 최종 — 이의·개정안을 받지 않음: \(id)"
        case .emptyReason: return "이의 이유가 비었음(--reason)"
        case .emptyScope: return "적용 범위가 비었음(--scope)"
        case .emptyContent: return "개정안 본문이 비었음(표준 입력에 바꿀 내용 전체)"
        case .caseNotFound(let id): return "이의·개정안 기록이 아님: \(id)"
        case .notPendingSupreme(let id): return "대법원 대기 건이 아님(항소심 대기이거나 이미 닫힘): \(id)"
        case .objectionPeriod(let until): return "이의 제기 기간 중 — \(until) 뒤에 결정할 수 있음"
        case .testimonyNotFound(let id): return "증언 기록을 찾을 수 없음: \(id)"
        case .testimonyNotUserEvidence(let id):
            return "증언은 speaker: user 인 증거(evidence) 기록이어야 함(드리밍 정리본 제외): \(id)"
        }
    }
}

/// 중재자 응답(JSON). 형식 판정은 `LawCourtService.judgment(from:…)` 한 곳.
public struct LawArbiterResponse: Decodable, Sendable, Equatable {
    public struct Action: Decodable, Sendable, Equatable {
        /// `restore`(묶음 원상회복) 또는 `amend`(개정 공포).
        public var kind: String?
        public var batch: String?
        public var title: String?
        public var body: String?
    }

    public var outcome: String?
    public var reason: String?
    /// 조문 개정안의 완화 여부.
    public var relaxes: Bool?
    public var action: Action?
}

/// 결정 뒤 조치 — 결정 기록을 `per-ruling` 으로 인용해 공포한다.
public enum LawCourtAction: Sendable, Equatable {
    case restore(batch: String)
    case amend(title: String?, body: String)
}

/// 판정된 결정(공포 전).
public struct LawCourtJudgment: Sendable, Equatable {
    public var outcome: LawRulingOutcome
    public var reason: String
    public var relaxes: Bool?
    public var action: LawCourtAction?
    /// 기계적으로 바꾼 사유(완화 → 회부 등).
    public var notes: [String] = []
}

/// 항소심 한 건의 결과.
public struct LawHearingEntry: Sendable, Equatable {
    public let caseID: String
    public let ruling: LawStoredRecord?
    public let outcome: LawRulingOutcome?
    public let arbiter: LawArbiterCandidate?
    /// 조치로 공포한 기록 id.
    public let actions: [String]
    public let notes: [String]
    /// 결정하지 않은 이유(다음 hear 에 다시).
    public let undecidedReason: String?
}

public struct LawHearingReport: Sendable, Equatable {
    public let entries: [LawHearingEntry]
    public var decided: [LawHearingEntry] { entries.filter { $0.ruling != nil } }
    public var undecided: [LawHearingEntry] { entries.filter { $0.ruling == nil } }
}

/// 대법원 결정 결과.
public struct LawCourtDecision: Sendable, Equatable {
    public let ruling: LawStoredRecord
    public let actions: [String]
    public let notes: [String]
}

public struct LawCourtService: Sendable {
    /// 결정 기록의 작성자 앱.
    public static let appSlug = "agent-wiki"

    public let target: LawLedgerTarget
    public let settings: LawCourtSettings
    public let runner: LawAIRunner
    public let appVersion: String

    public init(
        target: LawLedgerTarget, settings: LawCourtSettings? = nil, runner: LawAIRunner = .live,
        appVersion: String = LedgerVersion.current
    ) {
        self.target = target
        self.settings = settings ?? target.file?.court ?? LawCourtSettings()
        self.runner = runner
        self.appVersion = appVersion
    }

    public func docket() -> LawCourtDocket { LawCourtDocket.of(target, settings: settings) }

    func scope() -> LawScopeIndex { LawEnactService.scope(of: target) }

    // MARK: - 이의·개정안

    /// 이의 — 대상을 `appeals` 로 인용하고 본문에 이유. 대상은 그대로 현행이고 항소심(상고면 대법원) 대기에 오른다.
    @discardableResult
    public func appeal(
        _ targetID: String, reason: String, actor: LawActor, batch: String? = nil, now: Date = Date()
    ) throws -> LawStoredRecord {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { throw LawCourtError.emptyReason }
        let object = try caseTarget(targetID)
        let draft = LawDraft(
            actor: actor, title: "이의: \(Self.label(object))", type: LawRecordType.appeal.rawValue, batch: batch,
            cites: [LawCite(id: object.id, rel: LawRelation.appeals.rawValue)], body: reason + "\n")
        return try LawEnactService.enact(draft, target: target, path: .court, now: now)
    }

    /// 개정안 — 대상을 `proposes` 로 인용하고, 본문에 `scope` 머리 칸과 바꿀 내용 전체.
    @discardableResult
    public func propose(
        _ targetID: String, scope: String, content: String, actor: LawActor, batch: String? = nil, now: Date = Date()
    ) throws -> LawStoredRecord {
        let scope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scope.isEmpty else { throw LawCourtError.emptyScope }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LawCourtError.emptyContent }
        let object = try caseTarget(targetID)
        let draft = LawDraft(
            actor: actor, title: "개정안: \(Self.label(object))", type: LawRecordType.proposal.rawValue, batch: batch,
            cites: [LawCite(id: object.id, rel: LawRelation.proposes.rawValue)],
            body: "scope: \(scope)\n\n\(content)")
        return try LawEnactService.enact(draft, target: target, path: .court, now: now)
    }

    /// 이의·개정 대상. 대법원 결정은 최종이라 받지 않는다.
    func caseTarget(_ id: String) throws -> LawScopeObject {
        guard let object = scope().object(id: id) else { throw LawCourtError.targetNotFound(id) }
        if let law = object.law, law.type == LawRecordType.ruling.rawValue,
           (try? LawHeadFields.parse(body: law.body, type: law.type))?["level"] == LawRulingLevel.supreme.rawValue {
            throw LawCourtError.supremeRulingIsFinal(id)
        }
        return object
    }

    /// 개정안 본문에서 머리 칸(`scope`)을 뺀 바꿀 내용.
    public static func proposalContent(_ body: String) -> String {
        guard let range = body.range(of: "\n\n") else { return "" }
        return String(body[range.upperBound...])
    }

    static func label(_ object: LawScopeObject) -> String {
        object.law?.title ?? object.object.title ?? String(object.id.prefix(8))
    }

    // MARK: - 항소심

    /// 항소심 — 대기 건마다 중재자(대상 기록을 쓴 모델과 다른 모델)를 불러 결정(`level: appellate`)을 공포한다.
    /// 다른 모델이 없으면 AI 를 부르지 않고 대법원에 회부한다. 응답 형식이 틀리면 그 건은 결정하지 않는다.
    public func hear(now: Date = Date()) -> LawHearingReport {
        let docket = docket()
        let hearBatch = LedgerID.generate(now: now)
        var entries: [LawHearingEntry] = []
        for item in docket.appellatePending {
            entries.append(hearOne(item, docket: docket, batch: hearBatch, now: now))
        }
        return LawHearingReport(entries: entries)
    }

    func hearOne(_ item: LawCourtCase, docket: LawCourtDocket, batch: String, now: Date) -> LawHearingEntry {
        func undecided(_ reason: String, arbiter: LawArbiterCandidate? = nil) -> LawHearingEntry {
            LawHearingEntry(caseID: item.id, ruling: nil, outcome: nil, arbiter: arbiter, actions: [], notes: [],
                            undecidedReason: reason)
        }
        let index = scope()
        guard let object = index.object(id: item.target) else { return undecided("대상 기록을 찾을 수 없음: \(item.target)") }
        guard let caseRecord = docket.records.first(where: { $0.id == item.id }) else {
            return undecided("사건 기록을 찾을 수 없음")
        }
        let targetModel = object.law?.model
        let judgment: LawCourtJudgment
        let actor: LawActor
        let arbiter = settings.arbiter(forTargetModel: targetModel)
        if let arbiter {
            let request = LawAIRequest(
                cli: arbiter.cli, model: arbiter.model, effort: arbiter.effort,
                prompt: LawCourtPrompt.appellate(case: item, caseRecord: caseRecord, target: object))
            do {
                let response = try runner.runJSON(request, as: LawArbiterResponse.self)
                judgment = try Self.judgment(
                    from: response, case: item, caseRecord: caseRecord, target: object, records: docket.records)
            } catch {
                return undecided("\(error)", arbiter: arbiter)
            }
            actor = appActor(modelRecord: request.modelRecord)
        } else {
            judgment = LawCourtJudgment(
                outcome: .refer,
                reason: "대상 기록을 쓴 모델(\(targetModel ?? "미상"))과 다른 중재자 후보가 없어 대법원에 회부한다.")
            actor = appActor(modelRecord: nil)
        }
        do {
            let ruling = try enactRuling(
                level: .appellate, judgment: judgment, case: item, target: object, actor: actor,
                extraCites: [], batch: batch, now: now)
            let (actions, notes) = try perform(judgment.action, ruling: ruling, target: object, actor: actor, now: now)
            return LawHearingEntry(
                caseID: item.id, ruling: ruling, outcome: judgment.outcome, arbiter: arbiter, actions: actions,
                notes: judgment.notes + notes, undecidedReason: nil)
        } catch {
            return undecided("\(error)", arbiter: arbiter)
        }
    }

    /// 앱 작성자. AI 판단을 거쳤으면 그 runtime·model·effort 를 적고, 기계적 기록이면 모델 칸을 비운다.
    func appActor(modelRecord: LawModelRecord?) -> LawActor {
        LawActor(
            author: "app:\(Self.appSlug)", kind: .app, device: target.currentDevice,
            runtime: modelRecord?.runtime ?? LawRuntime.app.rawValue, model: modelRecord?.model,
            effort: modelRecord?.effort, app: Self.appSlug, appVersion: appVersion)
    }

    /// 중재자 응답 → 결정. 형식 오류면 던진다(그 건은 결정하지 않는다).
    /// - 조문(`article`) 개정안은 `relaxes` 가 있어야 하고, 완화이면 반드시 회부한다.
    /// - 확정 판결(`judgment` 유형, `status: confirmed` 인 판결 등록)을 뒤집는 결정은 대법원에 회부한다.
    public static func judgment(
        from response: LawArbiterResponse, case item: LawCourtCase, caseRecord: LawStoredRecord,
        target: LawScopeObject, records: [LawStoredRecord]
    ) throws -> LawCourtJudgment {
        func invalid(_ message: String) -> LawAIRunnerError { .invalidJSON(message) }
        guard let raw = response.outcome, let outcome = LawRulingOutcome(rawValue: raw),
              [.uphold, .overturn, .refer].contains(outcome)
        else { throw invalid("outcome 은 uphold|overturn|refer — 받은 값: \(response.outcome ?? "없음")") }
        guard let reason = response.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty else {
            throw invalid("reason 이 비었음")
        }
        let targetType = target.law?.type ?? target.object.type
        let isArticleProposal = item.kind == .proposal && targetType == LawRecordType.article.rawValue
        if isArticleProposal, response.relaxes == nil { throw invalid("조문 개정안은 relaxes(true|false)가 필요함") }
        var judgment = LawCourtJudgment(outcome: outcome, reason: reason, relaxes: isArticleProposal ? response.relaxes : nil)
        if isArticleProposal, response.relaxes == true, outcome != .refer {
            judgment.outcome = .refer
            judgment.notes.append("조문 완화 개정안 — 대법원에 회부(중재자 결과 \(outcome.rawValue))")
        }
        if judgment.outcome == .overturn, isConfirmedJudgment(target) {
            judgment.outcome = .refer
            judgment.notes.append("확정 판결의 변경 — 대법원에 회부")
        }
        guard judgment.outcome == .overturn else { return judgment }
        judgment.action = try action(from: response.action, case: item, caseRecord: caseRecord, target: target, records: records)
        return judgment
    }

    static func action(
        from raw: LawArbiterResponse.Action?, case item: LawCourtCase, caseRecord: LawStoredRecord,
        target: LawScopeObject, records: [LawStoredRecord]
    ) throws -> LawCourtAction {
        func invalid(_ message: String) -> LawAIRunnerError { .invalidJSON(message) }
        let kind = raw?.kind ?? (item.kind == .proposal ? "amend" : nil)
        switch kind {
        case "restore":
            guard let batch = raw?.batch?.trimmingCharacters(in: .whitespaces), !batch.isEmpty else {
                throw invalid("restore 조치에 batch 가 없음")
            }
            guard records.contains(where: { $0.record.batch == batch }) else { throw invalid("없는 묶음: \(batch)") }
            return .restore(batch: batch)
        case "amend":
            var body = raw?.body ?? ""
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.kind == .proposal {
                body = proposalContent(caseRecord.record.body)
            }
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid("amend 조치에 body 가 없음") }
            let type = target.law?.type ?? LawRecordType.record.rawValue
            do {
                _ = try LawHeadFields.parse(body: body, type: type)
            } catch {
                throw invalid("개정 본문의 머리 칸 오류: \(error)")
            }
            let title = raw?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            if title?.contains(where: \.isNewline) == true { throw invalid("title 은 한 줄") }
            return .amend(title: title?.isEmpty == false ? title : nil, body: body)
        default:
            throw invalid("뒤집기(overturn)는 action.kind 가 restore|amend 여야 함")
        }
    }

    /// 확정 판결 — `judgment` 유형, 또는 `status: confirmed` 인 판결 등록.
    static func isConfirmedJudgment(_ object: LawScopeObject) -> Bool {
        guard let law = object.law else { return false }
        if law.type == LawRecordType.judgment.rawValue { return true }
        guard law.type == LawRecordType.registration.rawValue else { return false }
        return (try? LawHeadFields.parse(body: law.body, type: law.type))?["status"]
            == LawRegistrationStatus.confirmed.rawValue
    }

    // MARK: - 대법원

    /// 대법원 결정 — 회부된 건·상고만, 공지 뒤 이의 기간이 지나야, 승인·기각을 말한 사용자 발화 증언
    /// (`speaker: user` 증거 기록을 `testifies`)이 있어야 공포한다. 작성자는 무관하다. 최종이다.
    @discardableResult
    public func decide(
        caseID: String, approve: Bool, testimony: String, actor: LawActor, batch: String? = nil, now: Date = Date()
    ) throws -> LawCourtDecision {
        let docket = docket()
        guard let item = docket.openCase(caseID), item.level == .supreme else {
            let isCase = docket.records.contains {
                $0.id == caseID && LawCourtCaseKind(recordType: $0.record.type) != nil
            }
            throw isCase ? LawCourtError.notPendingSupreme(caseID) : LawCourtError.caseNotFound(caseID)
        }
        if let decidable = item.decidableAt, now < decidable {
            throw LawCourtError.objectionPeriod(until: LawTime.format(decidable))
        }
        let index = scope()
        guard let evidence = index.object(id: testimony) else { throw LawCourtError.testimonyNotFound(testimony) }
        guard let law = evidence.law, law.type == LawRecordType.evidence.rawValue,
              law.speaker == LawSpeaker.user.rawValue, law.origin != LawOrigin.dream.rawValue
        else { throw LawCourtError.testimonyNotUserEvidence(testimony) }
        guard let object = index.object(id: item.target) else { throw LawCourtError.targetNotFound(item.target) }

        var judgment = LawCourtJudgment(
            outcome: approve ? .approve : .reject,
            reason: "사용자 결정(\(approve ? "승인" : "기각")) — 증언 \(testimony.prefix(8))")
        if approve, item.kind == .proposal, let caseRecord = docket.records.first(where: { $0.id == item.id }) {
            judgment.action = .amend(title: nil, body: Self.proposalContent(caseRecord.record.body))
        }
        let ruling = try enactRuling(
            level: .supreme, judgment: judgment, case: item, target: object, actor: actor,
            extraCites: [LawCite(id: testimony, rel: LawRelation.testifies.rawValue)], speaker: LawSpeaker.user.rawValue,
            batch: batch, now: now)
        var actions: [String] = []
        var notes: [String] = []
        if approve {
            if item.isFinalAppeal {
                // 상고 승인 — 상고한 항소심 결정에 따른 조치 묶음을 원상회복한다.
                let batches = Self.actionBatches(of: item.target, records: target.store.scan())
                if batches.isEmpty { notes.append("상고한 결정에 따른 조치가 없음 — 필요한 조치는 per-ruling 으로 공포") }
                for actionBatch in batches {
                    let (ids, more) = try perform(.restore(batch: actionBatch), ruling: ruling, target: object, actor: actor, now: now)
                    actions += ids
                    notes += more
                }
            } else {
                let (ids, more) = try perform(judgment.action, ruling: ruling, target: object, actor: actor, now: now)
                actions = ids
                notes = more
                if judgment.action == nil { notes.append("자동 조치 없음 — 필요한 조치는 이 결정을 per-ruling 으로 인용해 공포") }
            }
        }
        return LawCourtDecision(ruling: ruling, actions: actions, notes: notes)
    }

    /// 결정 `rulingID` 를 `per-ruling` 으로 인용한 조치 기록들의 묶음.
    static func actionBatches(of rulingID: String, records: [LawStoredRecord]) -> [String] {
        var seen: [String] = []
        for stored in records where stored.record.cites.contains(where: {
            $0.id == rulingID && $0.rel == LawRelation.perRuling.rawValue
        }) {
            if let batch = stored.record.batch, !seen.contains(batch) { seen.append(batch) }
        }
        return seen
    }

    // MARK: - 공포

    func enactRuling(
        level: LawRulingLevel, judgment: LawCourtJudgment, case item: LawCourtCase, target object: LawScopeObject,
        actor: LawActor, extraCites: [LawCite], speaker: String? = nil, batch: String?, now: Date
    ) throws -> LawStoredRecord {
        var lines = ["level: \(level.rawValue)", "outcome: \(judgment.outcome.rawValue)", "", judgment.reason]
        if let relaxes = judgment.relaxes { lines += ["", "조문 개정안 판정: \(relaxes ? "완화" : "강화")"] }
        if !judgment.notes.isEmpty { lines += [""] + judgment.notes.map { "- \($0)" } }
        let heading = level == .appellate ? "항소심 결정" : "대법원 결정"
        let draft = LawDraft(
            actor: actor, speaker: speaker, title: "\(heading): \(item.title ?? String(item.id.prefix(8)))",
            type: LawRecordType.ruling.rawValue, batch: batch,
            cites: [LawCite(id: item.id, rel: LawRelation.hears.rawValue), LawCite(id: object.id)] + extraCites,
            body: lines.joined(separator: "\n") + "\n")
        return try LawEnactService.enact(draft, target: target, path: .court, now: now)
    }

    /// 결정이 요구한 조치를 결정 기록을 `per-ruling` 으로 인용해 공포한다. 개정은 이 원장의 현행 기록에만 한다.
    func perform(
        _ action: LawCourtAction?, ruling: LawStoredRecord, target object: LawScopeObject, actor: LawActor, now: Date
    ) throws -> (ids: [String], notes: [String]) {
        guard let action else { return ([], []) }
        switch action {
        case .restore(let batch):
            let restored = try LawEnactService.restore(
                batch: batch, actor: actor, target: target, perRuling: ruling.id, now: now)
            return (restored.map(\.id), [])
        case .amend(let title, let body):
            let records = target.store.scan()
            guard object.world == target.worldName, !object.isPredecessor,
                  let current = records.first(where: { $0.id == object.id })?.record
            else { return ([], ["대상이 이 원장의 기록이 아님 — 개정은 per-ruling 으로 직접 공포"]) }
            guard LawLedgerView(records: records).isInForce(object.id) else {
                return ([], ["대상이 현행이 아님(이미 개정·폐지) — 개정은 per-ruling 으로 직접 공포"])
            }
            let draft = LawDraft(
                actor: actor, title: title ?? current.title, type: current.type ?? LawRecordType.record.rawValue,
                origin: current.origin == LawOrigin.dream.rawValue ? nil : current.origin,
                batch: LedgerID.generate(now: now), tags: current.tags,
                cites: current.cites + [LawCite(id: ruling.id, rel: LawRelation.perRuling.rawValue)],
                exhibits: current.exhibits, amends: object.id, source: current.source, body: body)
            let stored = try LawEnactService.enact(draft, target: target, path: .court, now: now)
            return ([stored.id], [])
        }
    }
}

// MARK: - 중재자 프롬프트

public enum LawCourtPrompt {
    static let bodyLimit = 20_000

    public static func appellate(case item: LawCourtCase, caseRecord: LawStoredRecord, target: LawScopeObject) -> String {
        let law = target.law
        let targetType = law?.type ?? target.object.type ?? "미상"
        let targetBody = String((law?.body ?? target.object.body).prefix(bodyLimit))
        let caseText: String
        switch item.kind {
        case .appeal:
            caseText = "## 이의(appeal)\n이유:\n\(caseRecord.record.body)"
        case .proposal:
            let scope = (try? LawHeadFields.parse(body: caseRecord.record.body, type: LawRecordType.proposal.rawValue))?["scope"] ?? ""
            caseText = "## 개정안(proposal)\n적용 범위: \(scope)\n바꿀 내용 전체:\n\(LawCourtService.proposalContent(caseRecord.record.body))"
        }
        return """
        당신은 agent-law 원장의 항소심 중재자다. 아래 사건 하나를 판단하고 JSON 객체 하나만 답한다.

        규칙:
        - outcome 은 "uphold"(대상 유지·이의/개정안 기각), "overturn"(뒤집기: 원상회복 또는 개정 공포), "refer"(대법원 회부) 중 하나.
        - 에이전트를 묶는 규칙을 완화하거나 확정 판결을 바꾸는 건은 "refer".
        - 대상이 조문(article)이고 사건이 개정안이면 relaxes(true=완화, false=강화)를 반드시 적는다. 완화이면 refer.
        - overturn 이면 action 을 적는다: {"kind":"restore","batch":"<원상회복할 묶음 id>"} 또는
          {"kind":"amend","title":"<새 제목, 생략 가능>","body":"<개정 본문 전체>"}. 개정안을 그대로 받아들이면 amend 의 body 를 생략해도 된다.
        - 개정은 소급하지 않는다. 규칙끼리 부딪히면 더 구체적인 쪽이 이긴다.
        - reason 에 판단 이유를 한국어로 적는다.

        응답 형식:
        {"outcome":"uphold|overturn|refer","reason":"...","relaxes":true|false,"action":{...}}

        ## 대상 기록
        id: \(target.id)
        유형: \(targetType)
        제목: \(law?.title ?? target.object.title ?? "")
        화자: \(law?.speaker ?? "")
        작성 모델: \(law?.model ?? "")
        묶음: \(law?.batch ?? target.object.batch ?? "")
        본문:
        \(targetBody)

        \(caseText)
        """
    }
}
