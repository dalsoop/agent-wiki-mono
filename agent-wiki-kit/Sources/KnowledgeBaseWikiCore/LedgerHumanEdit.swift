import Foundation
import WikiLedgerKit

// 화면 편집(사람이 쓰는 새 기록·개정·삭제·복구)의 쓰기 한 자리.
// ledger 3 원장이면 공포 경로(`LawEnactService` — 쓰기 게이트·기기 키·범위 해석기·후처리),
// ledger 2 원장이면 옛 발행(`LedgerStore.publish`)으로 간다. 두 형식 모두 보관된 원장(전신)에는 쓰지 않는다.
// 근거: docs/architecture.md "agent-law"(화면 편집도 같은 경로), 결정 0007.

public enum LedgerHumanEditAction: Sendable, Equatable {
    /// 새 기록.
    case create(title: String?, body: String, cites: [LedgerObject.Cite])
    /// 개정(본문·제목·인용을 바꾼 새 판).
    case amend(target: String, title: String?, body: String, cites: [LedgerObject.Cite])
    /// 삭제(ledger 3 폐지, ledger 2 철회).
    case repeal(target: String, reason: String)
    /// 삭제 복구(ledger 3 는 효력 있는 폐지 기록을 폐지, ledger 2 는 `restores` 인용 재발행).
    case restore(target: String)
}

public enum LedgerHumanEditError: Error, CustomStringConvertible {
    case writeDenied(WorldWriteDenial)
    case service(LawEnactServiceError)
    case notFound(String)
    case notRepealed(String)
    case ledgerTwo(Error)

    public var description: String {
        switch self {
        case .writeDenied(let denial): return denial.message
        case .service(let error): return error.description
        case .notFound(let id): return "기록을 찾을 수 없음: \(id)"
        case .notRepealed(let id): return "폐지되지 않은 기록: \(id)"
        case .ledgerTwo(let error): return "\(error)"
        }
    }
}

public enum LedgerHumanEdit {
    /// ledger 2 화면 편집의 옛 작성자 값(동작 유지).
    public static let ledgerTwoAuthor = "human"

    /// ledger 3 화면 편집의 작성자 — `user:<이름>`.
    public static func humanAuthor(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        "user:" + (environment["USER"].flatMap { $0.isEmpty ? nil : $0 } ?? NSUserName())
    }

    /// 화면 편집의 공포 주체 — 사람(모델 칸 비움, runtime human), 기기는 설정의 이 기기 키.
    public static func humanActor(author: String = humanAuthor(), device: String?) -> LawActor {
        LawActor(author: author, kind: .human, device: device, runtime: LawRuntime.human.rawValue)
    }

    /// 편집 하나를 쓰고 새 기록 id 를 돌려준다.
    @discardableResult
    public static func perform(
        _ action: LedgerHumanEditAction, target: LawLedgerTarget,
        author: String = humanAuthor(), now: Date = Date()
    ) throws -> String {
        if target.isLedgerThree { return try performLedgerThree(action, target: target, author: author, now: now) }
        if let denial = target.writeDenial() { throw LedgerHumanEditError.writeDenied(denial) }
        return try performLedgerTwo(action, store: LedgerStore(root: target.root), now: now)
    }

    static func lawCites(_ cites: [LedgerObject.Cite]) -> [LawCite] {
        cites.map { LawCite(id: $0.id, rel: LawRelation(rawValue: $0.rel)?.rawValue ?? LawRelation.cites.rawValue) }
    }

    static func performLedgerThree(
        _ action: LedgerHumanEditAction, target: LawLedgerTarget, author: String, now: Date
    ) throws -> String {
        let actor = humanActor(author: author, device: target.currentDevice)
        let records = target.store.scan()
        func record(_ id: String) throws -> LawRecord {
            guard let found = records.first(where: { $0.id == id })?.record else {
                throw LedgerHumanEditError.notFound(id)
            }
            return found
        }
        let draft: LawDraft
        switch action {
        case .create(let title, let body, let cites):
            draft = LawDraft(actor: actor, speaker: LawSpeaker.user.rawValue, title: title, cites: lawCites(cites), body: body)
        case .amend(let id, let title, let body, let cites):
            let previous = try record(id)
            draft = LawDraft(
                actor: actor, speaker: LawSpeaker.user.rawValue, title: title,
                type: previous.type ?? LawRecordType.record.rawValue, tags: previous.tags,
                cites: lawCites(cites), exhibits: previous.exhibits, amends: id, body: body)
        case .repeal(let id, let reason):
            let previous = try record(id)
            draft = LawDraft(
                actor: actor, speaker: LawSpeaker.user.rawValue, title: previous.title.map { "폐지: \($0)" },
                type: previous.type ?? LawRecordType.record.rawValue, repeals: id, body: reason)
        case .restore(let id):
            let view = LawLedgerView(records: records)
            // 효력 있는 폐지 기록(스스로 폐지되지 않은 것)을 폐지하면 대상이 다시 현행이 된다.
            guard let repealer = records.last(where: { $0.record.repeals == id && !view.repealed.contains($0.id) })
            else {
                throw LedgerHumanEditError.notRepealed(id)
            }
            draft = LawDraft(
                actor: actor, speaker: LawSpeaker.user.rawValue, title: repealer.record.title.map { "복구: \($0)" },
                type: repealer.record.type ?? LawRecordType.record.rawValue, repeals: repealer.id,
                body: "restore \(id)")
        }
        do {
            return try LawEnactService.enact(draft, target: target, now: now).id
        } catch let error as LawEnactServiceError {
            throw LedgerHumanEditError.service(error)
        }
    }

    static func performLedgerTwo(_ action: LedgerHumanEditAction, store: LedgerStore, now: Date) throws -> String {
        do {
            switch action {
            case .create(let title, let body, let cites):
                return try store.publish(author: ledgerTwoAuthor, title: title, body: body, cites: cites).id
            case .amend(let id, let title, let body, let cites):
                return try store.publish(
                    author: ledgerTwoAuthor, title: title, body: body, cites: cites, supersedes: id).id
            case .repeal(let id, let reason):
                return try store.publish(author: ledgerTwoAuthor, body: reason, retracts: id).id
            case .restore(let id):
                guard let head = store.scan().first(where: { $0.id == id }) else {
                    throw LedgerHumanEditError.notFound(id)
                }
                return try store.publish(
                    author: ledgerTwoAuthor, title: head.title, body: head.body,
                    cites: [.init(id: head.id, rel: "restores")]).id
            }
        } catch let error as LedgerHumanEditError {
            throw error
        } catch {
            throw LedgerHumanEditError.ledgerTwo(error)
        }
    }
}
