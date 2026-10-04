import Foundation
import SessionKit
import WikiLedgerKit

// 심급제 — 설정(중재자 후보·이의 기간)과 사건 목록(항소심 대기·대법원 대기·이의 기간 중 개정안).
// 근거: docs/business-rules.md "심급제"·"관계"(`appeals`·`proposes`·`hears`)·"본문 머리 칸"(`ruling`),
// 결정 0007(나무위키 규정 개정의 공지·이의 기간, 위키백과 중재 비교).
// 사건 목록은 원장 기록에서 계산하는 보기이고 저장하지 않는다.

// MARK: - 설정

/// 중재자 후보 하나 — 실행 도구(지원 CLI 목록)·정확한 모델 id·추론 강도.
public struct LawArbiterCandidate: Codable, Equatable, Sendable {
    public var cli: SupportedAIAgentCLI
    public var model: String
    public var effort: String?

    public init(cli: SupportedAIAgentCLI, model: String, effort: String? = nil) {
        self.cli = cli
        self.model = model
        self.effort = effort
    }
}

/// 호스트 설정의 심급 자리(`court`). 이의 기간은 비우면 기본값이고, 중재자 후보는 설정(`world ai arbiters`)에서만 받는다.
public struct LawCourtSettings: Codable, Equatable, Sendable {
    /// 중재자 후보(앞에서부터). 대상 기록의 `model` 과 다른 첫 후보가 중재한다.
    /// 비어 있으면 중재자가 없고, 항소심 사건은 대법원으로 회부된다(docs/business-rules.md "심급제").
    public var arbiters: [LawArbiterCandidate]?
    /// 대법원 공지 뒤 이의 제기 기간(시간).
    public var objectionPeriodHours: Double?

    public init(arbiters: [LawArbiterCandidate]? = nil, objectionPeriodHours: Double? = nil) {
        self.arbiters = arbiters
        self.objectionPeriodHours = objectionPeriodHours
    }

    public static let defaultObjectionPeriodHours: Double = 72

    /// 설정한 중재자 후보. 모델 이름은 소스에 두지 않는다(설정 `world ai arbiters --add`).
    public var resolvedArbiters: [LawArbiterCandidate] { arbiters ?? [] }

    public var objectionPeriod: TimeInterval {
        let hours = objectionPeriodHours.flatMap { $0 >= 0 ? $0 : nil } ?? Self.defaultObjectionPeriodHours
        return hours * 3600
    }

    /// 대상 기록을 쓴 모델과 다른 첫 후보. 다른 모델이 없으면 nil(그 건은 대법원으로 간다).
    public func arbiter(forTargetModel targetModel: String?) -> LawArbiterCandidate? {
        let written = targetModel?.trimmingCharacters(in: .whitespaces)
        return resolvedArbiters.first { candidate in
            candidate.cli.supportsUnattendedRun && candidate.model != written
        }
    }
}

// MARK: - 사건

public enum LawCourtCaseKind: String, Sendable, Equatable, Codable {
    case appeal, proposal

    init?(recordType: String?) {
        switch recordType {
        case LawRecordType.appeal.rawValue: self = .appeal
        case LawRecordType.proposal.rawValue: self = .proposal
        default: return nil
        }
    }

    var relation: LawRelation { self == .appeal ? .appeals : .proposes }
}

/// 열린 사건 하나 — 이의 또는 개정안 기록과 그것이 대기 중인 심급.
public struct LawCourtCase: Sendable, Equatable {
    /// 이의·개정안 기록 id.
    public let id: String
    public let kind: LawCourtCaseKind
    /// 대기 중인 심급.
    public let level: LawRulingLevel
    /// 이의·개정 대상 기록 id.
    public let target: String
    public let title: String?
    public let filed: Date
    /// 상고 — 결정(`ruling`)에 대한 이의.
    public let isFinalAppeal: Bool
    /// 대법원으로 회부한 항소심 결정 id(상고면 nil).
    public let referredBy: String?
    /// 공지 시각 — 대법원 대기면 회부 결정의 공포일(상고는 상고 기록의 공포일), 항소심 대기면 제기일.
    public let noticedAt: Date
    /// 결정할 수 있는 시각(대법원 대기만) = 공지 + 이의 기간.
    public let decidableAt: Date?

    public func isInObjectionPeriod(now: Date, period: TimeInterval) -> Bool {
        now < noticedAt.addingTimeInterval(period)
    }
}

/// 목차 맨 위에 공지할 것 — 대법원 대기 건과 이의 기간 중인 개정안.
public struct LawCourtNotices: Sendable, Equatable {
    public let supreme: [LawCourtCase]
    public let proposalsInObjection: [LawCourtCase]
}

/// 원장 기록에서 계산한 사건 목록. 저장하지 않는다.
public struct LawCourtDocket: Sendable {
    public let records: [LawStoredRecord]
    public let objectionPeriod: TimeInterval
    /// 열린 사건(항소심·대법원 대기). 제기 순.
    public let open: [LawCourtCase]

    public init(records: [LawStoredRecord], objectionPeriod: TimeInterval = LawCourtSettings.defaultObjectionPeriodHours * 3600) {
        self.records = records
        self.objectionPeriod = objectionPeriod
        let view = LawLedgerView(records: records)
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // 현행 결정 → 심급·결과·다룬 건. 규칙을 지킨 결정만 사건을 닫는다(위조 결정으로 사건이 닫히지 않게):
        // 항소심은 `app:agent-wiki` 가 대상 기록과 다른 모델로, 대법원은 이의 기간 뒤 사용자 발화 증언을 인용해야 한다.
        var appellate: [String: LawStoredRecord] = [:]
        var supremeRulings: [(caseID: String, ruling: LawStoredRecord)] = []
        for ruling in records where ruling.record.type == LawRecordType.ruling.rawValue && view.isInForce(ruling.id) {
            guard let head = Self.rulingHead(ruling) else { continue }
            for cite in ruling.record.cites where cite.rel == LawRelation.hears.rawValue {
                switch head.level {
                case .supreme: supremeRulings.append((cite.id, ruling))
                case .appellate:
                    guard Self.isValidAppellate(ruling, outcome: head.outcome, caseID: cite.id, byID: byID) else { continue }
                    appellate[cite.id] = ruling  // 공포 순이라 마지막이 가장 늦다
                }
            }
        }
        var supreme: Set<String> = []
        for entry in supremeRulings where Self.isValidSupreme(
            entry.ruling, caseID: entry.caseID, appellate: appellate, byID: byID, objectionPeriod: objectionPeriod) {
            supreme.insert(entry.caseID)
        }

        var open: [LawCourtCase] = []
        for stored in records where view.isInForce(stored.id) {
            guard let kind = LawCourtCaseKind(recordType: stored.record.type), !supreme.contains(stored.id),
                  let target = stored.record.cites.first(where: { $0.rel == kind.relation.rawValue })?.id
            else { continue }
            let isFinalAppeal = kind == .appeal && byID[target]?.record.type == LawRecordType.ruling.rawValue
            let filed = stored.record.promulgated
            if let ruling = appellate[stored.id] {
                guard Self.rulingHead(ruling)?.outcome == .refer else { continue }  // 항소심에서 닫힘
                let notice = ruling.record.promulgated
                open.append(LawCourtCase(
                    id: stored.id, kind: kind, level: .supreme, target: target, title: stored.record.title,
                    filed: filed, isFinalAppeal: isFinalAppeal, referredBy: ruling.id, noticedAt: notice,
                    decidableAt: notice.addingTimeInterval(objectionPeriod)))
            } else if isFinalAppeal {
                open.append(LawCourtCase(
                    id: stored.id, kind: kind, level: .supreme, target: target, title: stored.record.title,
                    filed: filed, isFinalAppeal: true, referredBy: nil, noticedAt: filed,
                    decidableAt: filed.addingTimeInterval(objectionPeriod)))
            } else {
                open.append(LawCourtCase(
                    id: stored.id, kind: kind, level: .appellate, target: target, title: stored.record.title,
                    filed: filed, isFinalAppeal: false, referredBy: nil, noticedAt: filed, decidableAt: nil))
            }
        }
        self.open = open
    }

    public var appellatePending: [LawCourtCase] { open.filter { $0.level == .appellate } }
    public var supremePending: [LawCourtCase] { open.filter { $0.level == .supreme } }

    public func cases(level: LawRulingLevel?) -> [LawCourtCase] {
        level.map { level in open.filter { $0.level == level } } ?? open
    }

    public func openCase(_ id: String) -> LawCourtCase? { open.first { $0.id == id } }

    /// 목차 맨 위 공지: 대법원 대기(공지 순) · 이의 기간 중인 개정안(공지 뒤 기간이 안 지난 열린 개정안).
    public func notices(now: Date = Date()) -> LawCourtNotices {
        LawCourtNotices(
            supreme: supremePending.sorted { ($0.noticedAt, $0.id) < ($1.noticedAt, $1.id) },
            proposalsInObjection: open.filter {
                $0.kind == .proposal && $0.isInObjectionPeriod(now: now, period: objectionPeriod)
            })
    }

    /// 사건 기록이 다투는 대상 id(`appeals`·`proposes`).
    static func caseTarget(_ caseID: String, byID: [String: LawStoredRecord]) -> String? {
        guard let stored = byID[caseID], let kind = LawCourtCaseKind(recordType: stored.record.type) else { return nil }
        return stored.record.cites.first { $0.rel == kind.relation.rawValue }?.id
    }

    /// 항소심 결정이 사건을 닫을 수 있나 — 작성자 `app:agent-wiki`(앱 공포), 판단한 모델이 대상 기록을 쓴 모델과 다름.
    /// 유지·뒤집기는 판단한 모델이 있어야 하고, 다른 모델이 없어 AI 없이 낸 회부만 모델 칸이 빈다.
    static func isValidAppellate(
        _ ruling: LawStoredRecord, outcome: LawRulingOutcome, caseID: String, byID: [String: LawStoredRecord]
    ) -> Bool {
        let record = ruling.record
        guard record.author == "app:\(LawCourtService.appSlug)", record.authorKind == LawAuthorKind.app.rawValue,
              record.app == LawCourtService.appSlug, byID[caseID] != nil
        else { return false }
        let model = record.model?.trimmingCharacters(in: .whitespaces)
        let targetModel = caseTarget(caseID, byID: byID).flatMap { byID[$0]?.record.model }?
            .trimmingCharacters(in: .whitespaces)
        if let model, !model.isEmpty {
            return model != targetModel
        }
        return outcome == .refer
    }

    /// 대법원 결정이 사건을 닫을 수 있나 — 대법원 대기였던 사건(항소심 회부 또는 상고)이고, 공지 뒤 이의 기간이 지나
    /// 공포됐고, `speaker: user` 증거를 `testifies` 로 인용했다. 같은 원장에 없는 증언(상위 사슬)은 공포 검증이 확인했다.
    static func isValidSupreme(
        _ ruling: LawStoredRecord, caseID: String, appellate: [String: LawStoredRecord],
        byID: [String: LawStoredRecord], objectionPeriod: TimeInterval
    ) -> Bool {
        guard let caseRecord = byID[caseID], let kind = LawCourtCaseKind(recordType: caseRecord.record.type),
              let target = caseTarget(caseID, byID: byID)
        else { return false }
        let noticedAt: Date
        if let referral = appellate[caseID], rulingHead(referral)?.outcome == .refer {
            noticedAt = referral.record.promulgated
        } else if kind == .appeal, byID[target]?.record.type == LawRecordType.ruling.rawValue {
            noticedAt = caseRecord.record.promulgated
        } else {
            return false
        }
        guard ruling.record.promulgated >= noticedAt.addingTimeInterval(objectionPeriod) else { return false }
        return ruling.record.cites.contains { cite in
            guard cite.rel == LawRelation.testifies.rawValue else { return false }
            guard let evidence = byID[cite.id]?.record else { return true }
            return evidence.type == LawRecordType.evidence.rawValue && evidence.speaker == LawSpeaker.user.rawValue
                && evidence.origin != LawOrigin.dream.rawValue
        }
    }

    /// 결정 기록의 머리 칸(`level`·`outcome`).
    public static func rulingHead(_ stored: LawStoredRecord) -> (level: LawRulingLevel, outcome: LawRulingOutcome)? {
        guard let head = try? LawHeadFields.parse(body: stored.record.body, type: LawRecordType.ruling.rawValue),
              let level = head["level"].flatMap(LawRulingLevel.init(rawValue:)),
              let outcome = head["outcome"].flatMap(LawRulingOutcome.init(rawValue:))
        else { return nil }
        return (level, outcome)
    }
}

extension LawCourtDocket {
    /// 원장 하나의 사건 목록(설정의 이의 기간).
    public static func of(_ target: LawLedgerTarget, settings: LawCourtSettings? = nil) -> LawCourtDocket {
        LawCourtDocket(
            records: target.store.scan(),
            objectionPeriod: (settings ?? target.file?.court ?? LawCourtSettings()).objectionPeriod)
    }
}
