import Foundation
import WikiLedgerKit

// 드리밍 제안과 안전 검사. AI 가 낸 정리 제안을 하나씩 검사해 적용할 변경·미룰 제안·버릴 제안·경보로 나눈다.
// 근거: docs/business-rules.md "드리밍"(할 수 없는 것·안전장치·쓰일 때만 이관), "출처 표시"(정리본은 증거로 인용 불가,
// 이관은 `migrated-from` 필수·옮기는 곳은 그 전신을 가진 원장), "심급제"(드리밍이 못 하는 변경은 항소심 개정안·이관 신청).

// MARK: - AI 응답

public struct LawDreamCite: Codable, Sendable, Equatable {
    public var id: String
    public var rel: String?

    public init(id: String, rel: String? = nil) {
        self.id = id
        self.rel = rel
    }
}

/// 정리 제안 하나. `kind` 별로 쓰는 칸이 다르다.
/// - `amend`: target(+also 병합), title?, body, tags?, cites?
/// - `repeal`: target, reason
/// - `enact`: title, body, type?(record 만), tags?, cites?
/// - `finding`: target, subject, certainty, domain, reason, from?, until?
/// - `migrate`: target(전신 객체), title?, body?, tags?, 사실인정 칸(subject·certainty·domain·reason)
/// - `alert`: message
public struct LawDreamProposal: Codable, Sendable, Equatable {
    public var kind: String
    public var target: String?
    public var also: [String]?
    public var title: String?
    public var type: String?
    public var body: String?
    public var tags: [String]?
    public var cites: [LawDreamCite]?
    public var reason: String?
    public var subject: String?
    public var certainty: String?
    public var domain: String?
    public var from: String?
    public var until: String?
    public var scope: String?
    public var message: String?

    public init(
        kind: String, target: String? = nil, also: [String]? = nil, title: String? = nil, type: String? = nil,
        body: String? = nil, tags: [String]? = nil, cites: [LawDreamCite]? = nil, reason: String? = nil,
        subject: String? = nil, certainty: String? = nil, domain: String? = nil, from: String? = nil,
        until: String? = nil, scope: String? = nil, message: String? = nil
    ) {
        self.kind = kind
        self.target = target
        self.also = also
        self.title = title
        self.type = type
        self.body = body
        self.tags = tags
        self.cites = cites
        self.reason = reason
        self.subject = subject
        self.certainty = certainty
        self.domain = domain
        self.from = from
        self.until = until
        self.scope = scope
        self.message = message
    }

    /// 보고에 쓰는 짧은 이름.
    public var label: String {
        let target = self.target.map { " \($0.prefix(8))" } ?? ""
        return "\(kind)\(target)"
    }
}

/// AI 응답 전체. `proposals` 가 없으면 형식 오류다.
public struct LawDreamResponse: Decodable, Sendable, Equatable {
    public var proposals: [LawDreamProposal]?
}

// MARK: - 계획

/// 검사를 통과한 변경 하나(공포 전).
public enum LawDreamChange: Sendable, Equatable {
    case amend(world: String, target: String, also: [String], title: String?, body: String, tags: [String]?, cites: [LawCite])
    case repeal(world: String, target: String, reason: String)
    case enact(world: String, title: String, body: String, tags: [String], cites: [LawCite])
    case finding(world: String, target: String, body: String)
    case migrate(world: String, predecessor: String, title: String, body: String, tags: [String], findingHead: [String])
    /// 드리밍이 직접 못 하는 개정·폐지 → 항소심 개정안.
    case propose(world: String, target: String, scope: String, content: String)
    /// 전신 판결 이관 → 항소심 이관 신청(이의).
    case appeal(world: String, target: String, reason: String)

    public var kind: String {
        switch self {
        case .amend: return "amend"
        case .repeal: return "repeal"
        case .enact: return "enact"
        case .finding: return "finding"
        case .migrate: return "migrate"
        case .propose: return "propose"
        case .appeal: return "appeal"
        }
    }

    public var isRepeal: Bool { if case .repeal = self { return true } else { return false } }
}

public struct LawDreamDiscard: Codable, Sendable, Equatable {
    public var proposal: String
    public var reason: String

    public init(proposal: String, reason: String) {
        self.proposal = proposal
        self.reason = reason
    }
}

public struct LawDreamPlan: Sendable, Equatable {
    public var changes: [(change: LawDreamChange, proposal: LawDreamProposal, note: String?)] = []
    public var deferred: [LawDreamProposal] = []
    public var discarded: [LawDreamDiscard] = []
    public var alerts: [String] = []

    public static func == (lhs: LawDreamPlan, rhs: LawDreamPlan) -> Bool {
        lhs.changes.map(\.change) == rhs.changes.map(\.change) && lhs.deferred == rhs.deferred
            && lhs.discarded == rhs.discarded && lhs.alerts == rhs.alerts
    }

    public var repealCount: Int { changes.filter { $0.change.isRepeal }.count }
}

/// 원장 하나의 제안 검사기.
public struct LawDreamPlanner {
    /// 처리 중인 원장.
    public let world: String
    public let index: LawScopeIndex
    /// 재료 세션이 찾거나 인용한 전신 객체 id.
    public let foundPredecessors: Set<String>
    /// 드리밍 대상 원장(world 이름) — 이관이 옮겨 갈 수 있는 곳.
    public let dreamWorlds: Set<String>
    /// 원장(world 이름) → 기록. 이관 중복·현행 판정에 쓴다.
    public let recordsByWorld: [String: [LawStoredRecord]]
    public let maxChanges: Int

    public init(
        world: String, index: LawScopeIndex, foundPredecessors: Set<String>, dreamWorlds: Set<String>,
        recordsByWorld: [String: [LawStoredRecord]], maxChanges: Int
    ) {
        self.world = world
        self.index = index
        self.foundPredecessors = foundPredecessors
        self.dreamWorlds = dreamWorlds
        self.recordsByWorld = recordsByWorld
        self.maxChanges = maxChanges
    }

    struct Refused: Error {
        let reason: String
        init(_ reason: String) { self.reason = reason }
    }

    /// 제안들을 순서대로 검사한다. 상한을 넘는 통과 제안은 다음 실행으로 미룬다.
    public func plan(_ proposals: [LawDreamProposal]) -> LawDreamPlan {
        var plan = LawDreamPlan()
        for proposal in proposals {
            if proposal.kind == "alert" {
                let message = LawContents.oneLine(proposal.message ?? proposal.reason ?? "")
                if message.isEmpty {
                    plan.discarded.append(LawDreamDiscard(proposal: proposal.label, reason: "경보 문구가 비었음"))
                } else {
                    plan.alerts.append(message)
                }
                continue
            }
            do {
                let (change, note) = try check(proposal)
                if plan.changes.count >= maxChanges {
                    plan.deferred.append(proposal)
                } else {
                    plan.changes.append((change, proposal, note))
                }
            } catch let refused as Refused {
                plan.discarded.append(LawDreamDiscard(proposal: proposal.label, reason: refused.reason))
            } catch {
                plan.discarded.append(LawDreamDiscard(proposal: proposal.label, reason: "\(error)"))
            }
        }
        return plan
    }

    // MARK: 검사

    func check(_ proposal: LawDreamProposal) throws -> (LawDreamChange, String?) {
        switch proposal.kind {
        case "amend": return try checkAmend(proposal)
        case "repeal": return try checkRepeal(proposal)
        case "enact": return (try checkEnact(proposal), nil)
        case "finding": return (try checkFinding(proposal), nil)
        case "migrate": return try checkMigrate(proposal)
        default: throw Refused("모르는 제안 종류: \(proposal.kind)")
        }
    }

    /// 이 원장의 현행 기록 하나.
    func ownRecord(_ token: String?) throws -> LawScopeObject {
        guard let token = token?.trimmingCharacters(in: .whitespaces), !token.isEmpty else {
            throw Refused("대상(target)이 없음")
        }
        let matches = index.idMatches(token)
        guard matches.count == 1, let object = matches.first else {
            throw Refused("대상 기록을 찾을 수 없음: \(token) — 저장소의 판결·조문은 고칠 수 없다(경보로 알린다)")
        }
        guard object.world == world, object.law != nil else {
            throw Refused("이 원장의 기록이 아님(\(object.world)): \(token)")
        }
        let view = LawLedgerView(records: recordsByWorld[world] ?? [])
        guard view.isInForce(object.id) else { throw Refused("현행 기록이 아님: \(object.id.prefix(8))") }
        return object
    }

    static func isProtected(_ law: LawRecord) -> String? {
        if law.speaker == LawSpeaker.user.rawValue { return "speaker: user 기록" }
        if law.type == LawRecordType.article.rawValue { return "조문(article)" }
        return nil
    }

    func checkAmend(_ proposal: LawDreamProposal) throws -> (LawDreamChange, String?) {
        let object = try ownRecord(proposal.target)
        guard let law = object.law else { throw Refused("ledger 3 기록이 아님") }
        guard let body = nonEmpty(proposal.body) else { throw Refused("개정 본문(body)이 비었음") }
        if law.type == LawRecordType.judgment.rawValue { throw Refused("judgment 는 드리밍이 개정할 수 없음") }
        if let protected = Self.isProtected(law) {
            let scope = nonEmpty(proposal.scope) ?? "드리밍 개정안"
            return (.propose(world: world, target: object.id, scope: scope, content: body),
                    "\(protected) 직접 개정 → 항소심 개정안")
        }
        guard law.type == LawRecordType.record.rawValue else {
            throw Refused("드리밍은 record 만 개정한다(유형 \(law.type ?? "?"))")
        }
        var also: [String] = []
        for token in proposal.also ?? [] {
            let other = try ownRecord(token)
            guard let otherLaw = other.law, otherLaw.type == LawRecordType.record.rawValue,
                  Self.isProtected(otherLaw) == nil
            else { throw Refused("병합 대상 \(other.id.prefix(8)) 은 드리밍이 개정할 수 없음(record·보호 기록 아님)") }
            if other.id != object.id, !also.contains(other.id) { also.append(other.id) }
        }
        let cites = try checkCites(proposal.cites)
        return (.amend(world: world, target: object.id, also: also, title: nonEmptyLine(proposal.title), body: body,
                       tags: proposal.tags, cites: cites), nil)
    }

    func checkRepeal(_ proposal: LawDreamProposal) throws -> (LawDreamChange, String?) {
        let object = try ownRecord(proposal.target)
        guard let law = object.law else { throw Refused("ledger 3 기록이 아님") }
        let reason = nonEmpty(proposal.reason) ?? "드리밍 정리"
        if law.type == LawRecordType.judgment.rawValue { throw Refused("judgment 는 드리밍이 폐지할 수 없음") }
        if let protected = Self.isProtected(law) {
            return (.propose(world: world, target: object.id, scope: nonEmpty(proposal.scope) ?? "폐지",
                             content: "폐지 제안: \(reason)\n"),
                    "\(protected) 폐지 → 항소심 개정안")
        }
        guard law.type == LawRecordType.record.rawValue else {
            throw Refused("드리밍은 record 만 폐지한다(유형 \(law.type ?? "?"))")
        }
        return (.repeal(world: world, target: object.id, reason: reason), nil)
    }

    func checkEnact(_ proposal: LawDreamProposal) throws -> LawDreamChange {
        let type = proposal.type ?? LawRecordType.record.rawValue
        if type == LawRecordType.judgment.rawValue { throw Refused("judgment 는 드리밍이 공포할 수 없음") }
        guard type == LawRecordType.record.rawValue else { throw Refused("드리밍의 새 기록은 record 만(받은 유형 \(type))") }
        guard let title = nonEmptyLine(proposal.title) else { throw Refused("새 기록의 제목(title)이 없음") }
        guard let body = nonEmpty(proposal.body) else { throw Refused("새 기록의 본문(body)이 비었음") }
        return .enact(world: world, title: title, body: body, tags: proposal.tags ?? [], cites: try checkCites(proposal.cites))
    }

    func checkFinding(_ proposal: LawDreamProposal) throws -> LawDreamChange {
        let object = try ownRecord(proposal.target)
        guard let law = object.law, LawRecordType.isKnowledge(law.type) else {
            throw Refused("사실인정 대상은 지식 기록이어야 함")
        }
        if law.origin == LawOrigin.dream.rawValue { throw Refused("정리본(origin: dream)은 사실인정 대상이 될 수 없음") }
        let body = try findingHead(proposal).joined(separator: "\n") + "\n"
        let view = LawLedgerView(records: recordsByWorld[world] ?? [])
        if let current = view.currentFinding(for: object.id), current.record.speaker == LawSpeaker.user.rawValue {
            return .propose(world: world, target: current.id, scope: nonEmptyLine(proposal.scope) ?? "사실인정 개정안",
                            content: body)
        }
        return .finding(world: world, target: object.id, body: body)
    }

    func checkMigrate(_ proposal: LawDreamProposal) throws -> (LawDreamChange, String?) {
        guard let token = proposal.target?.trimmingCharacters(in: .whitespaces), !token.isEmpty else {
            throw Refused("대상(target)이 없음")
        }
        let matches = index.idMatches(token)
        guard matches.count == 1, let object = matches.first, object.isPredecessor else {
            throw Refused("전신 객체가 아님: \(token)")
        }
        guard foundPredecessors.contains(object.id) else {
            throw Refused("재료 세션이 찾거나 인용한 전신 객체가 아님(쓰일 때만 이관): \(object.id.prefix(8))")
        }
        guard let destination = index.catalog.successorNames(of: object.world).first(where: dreamWorlds.contains) else {
            throw Refused("전신 \(object.world) 를 가진 원장이 드리밍 대상에 없음")
        }
        let reasonText = nonEmpty(proposal.reason) ?? "재료 세션에서 쓰임"
        if object.object.effectiveType == "decision" {
            return (.appeal(world: destination, target: object.id, reason: "전신 판결 이관 신청: \(reasonText)\n"),
                    "전신 판결 이관 → 항소심 이관 신청")
        }
        let already = (recordsByWorld[destination] ?? []).contains { stored in
            stored.record.cites.contains { $0.id == object.id && $0.rel == LawRelation.migratedFrom.rawValue }
        }
        if already { throw Refused("이미 이관됨: \(object.id.prefix(8))") }
        guard let title = nonEmptyLine(proposal.title) ?? nonEmptyLine(object.object.title) else {
            throw Refused("이관 기록의 제목이 없음")
        }
        guard let body = nonEmpty(proposal.body) ?? nonEmpty(object.object.body) else { throw Refused("이관 본문이 비었음") }
        let head = try findingHead(proposal)
        return (.migrate(world: destination, predecessor: object.id, title: title, body: body,
                         tags: proposal.tags ?? object.object.tags, findingHead: head), nil)
    }

    /// 사실인정 머리 칸(정의 순서). 값 검사는 머리 칸 정본(`LawHeadFields`)이 한다.
    func findingHead(_ proposal: LawDreamProposal) throws -> [String] {
        let values: [String: String?] = [
            "subject": nonEmptyLine(proposal.subject), "certainty": nonEmptyLine(proposal.certainty),
            "effective-from": nonEmptyLine(proposal.from), "effective-until": nonEmptyLine(proposal.until),
            "domain": nonEmptyLine(proposal.domain), "reason": nonEmptyLine(proposal.reason),
        ]
        let lines = (LawHeadFields.keysByType[.finding] ?? []).compactMap { key -> String? in
            guard let value = values[key] ?? nil else { return nil }
            return "\(key): \(value)"
        }
        do {
            _ = try LawHeadFields.parse(body: lines.joined(separator: "\n") + "\n", type: LawRecordType.finding.rawValue)
        } catch {
            throw Refused("사실인정 칸 오류: \(error)")
        }
        return lines
    }

    /// 인용 — `cites`·`testifies` 만. 정리본을 증거(testifies)로 인용하면 버린다.
    func checkCites(_ raw: [LawDreamCite]?) throws -> [LawCite] {
        var cites: [LawCite] = []
        for item in raw ?? [] {
            let rel = item.rel ?? LawRelation.cites.rawValue
            guard rel == LawRelation.cites.rawValue || rel == LawRelation.testifies.rawValue else {
                throw Refused("드리밍 제안이 쓸 수 없는 관계: \(rel)")
            }
            let matches = index.idMatches(item.id)
            guard matches.count == 1, let object = matches.first else { throw Refused("인용 대상을 찾을 수 없음: \(item.id)") }
            let origin = object.law?.origin ?? object.object.origin
            if rel == LawRelation.testifies.rawValue, origin == LawOrigin.dream.rawValue {
                throw Refused("정리본(origin: dream)을 증거로 인용할 수 없음: \(object.id.prefix(8))")
            }
            let cite = LawCite(id: object.id, rel: rel)
            if !cites.contains(cite) { cites.append(cite) }
        }
        return cites
    }

    func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text.hasSuffix("\n") ? text : text + "\n"
    }

    func nonEmptyLine(_ text: String?) -> String? {
        let line = LawContents.oneLine(text ?? "")
        return line.isEmpty ? nil : line
    }
}
