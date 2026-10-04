import Foundation
import WikiLedgerKit

/// 공포 검증 — 규칙을 통과한 기록(정규화·기본값 적용)을 만든다. 공포 경로(`LawStore.enact`)만 부른다.
/// 근거: docs/business-rules.md "작성자와 모델 기록"·"화자"·"관계"·"출처 표시"·"공포·개정·폐지·원상회복".
struct LawEnactValidator {
    let store: LawStore
    let context: LawEnactContext
    let sameLedger: LawSameLedgerResolver

    func resolve(_ id: String) -> LawResolvedReference? {
        sameLedger.resolve(id) ?? context.resolver?.resolve(id)
    }

    func validatedRecord(_ draft: LawDraft, promulgated: Date) throws -> LawRecord {
        guard let type = LawRecordType(rawValue: draft.type) else { throw LawEnactError.unknownType(draft.type) }
        let actor = try validatedActor(draft.actor)
        try checkValue("speaker", draft.speaker, LawSpeaker.self)
        try checkValue("origin", draft.origin, LawOrigin.self)
        try checkSingleLine(draft, actor: actor)
        for sha in draft.exhibits where !LawHash.isContentID(sha) { throw LawEnactError.invalidExhibit(sha) }

        if draft.repeals == nil, draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw LawEnactError.emptyBody
        }
        let head: LawHeadFieldBlock
        do {
            head = try LawHeadFields.parse(body: draft.body, type: type.rawValue)
        } catch let error as LawHeadFieldError {
            throw LawEnactError.headField(error)
        }

        let resolved = try checkReferences(draft, type: type)
        try checkOrigin(draft)
        let speaker = try resolvedSpeaker(draft, type: type, actor: actor, head: head, resolved: resolved)

        let authorship = LawAuthorship(
            authorKind: actor.kind.rawValue, device: actor.device, runtime: actor.runtime,
            runtimeVersion: actor.runtimeVersion, model: actor.model, effort: actor.effort,
            app: actor.app, appVersion: actor.appVersion, speaker: speaker)
        let relations = LawRelations(
            cites: draft.cites, exhibits: draft.exhibits, amends: draft.amends,
            amendsAlso: draft.amendsAlso, repeals: draft.repeals)
        return LawRecord(
            promulgated: promulgated, author: actor.author, authorship: authorship,
            title: draft.title, type: type.rawValue, origin: draft.origin, batch: draft.batch,
            tags: draft.tags, relations: relations, source: draft.source, body: draft.body, cost: draft.cost
        ).nfcNormalized()
    }

    // MARK: - 작성자와 모델 기록

    func validatedActor(_ input: LawActor) throws -> LawActor {
        var actor = input
        func blank(_ s: String?) -> Bool { s?.trimmingCharacters(in: .whitespaces).isEmpty ?? true }
        try checkValue("runtime", actor.runtime, LawRuntime.self)
        try checkValue("effort", actor.effort, LawEffort.self)
        switch actor.kind {
        case .agent:
            guard !blank(actor.runtime) else { throw LawEnactError.runtimeUnknown }
            guard !blank(actor.model) else { throw LawEnactError.modelUnknown }
            if blank(actor.effort) { actor.effort = LawEffort.unknown.rawValue }
        case .app:
            guard !blank(actor.app), !blank(actor.appVersion) else { throw LawEnactError.appIdentityMissing }
            // AI 판단을 거친 앱 기록은 그 판단의 runtime·model·effort 를 적는다. 판단 없는 기록은 모델 칸을 비운다.
            if !blank(actor.model) {
                guard !blank(actor.runtime) else { throw LawEnactError.runtimeUnknown }
                if blank(actor.effort) { actor.effort = LawEffort.unknown.rawValue }
            }
        case .human:
            guard blank(actor.model), blank(actor.effort), blank(actor.runtimeVersion),
                  blank(actor.runtime) || actor.runtime == LawRuntime.human.rawValue
            else { throw LawEnactError.humanModelFields }
        }
        return actor
    }

    func checkValue<E: CaseIterable & RawRepresentable>(_ field: String, _ value: String?, _: E.Type) throws
        where E.RawValue == String {
        guard let value, !value.isEmpty else { return }
        guard E(rawValue: value) != nil else { throw LawEnactError.valueNotAllowed(field: field, value: value) }
    }

    func checkSingleLine(_ draft: LawDraft, actor: LawActor) throws {
        let fields: [(String, String?)] = [
            ("author", actor.author), ("device", actor.device), ("runtime-version", actor.runtimeVersion),
            ("model", actor.model), ("app", actor.app), ("app-version", actor.appVersion),
            ("title", draft.title), ("batch", draft.batch), ("amends", draft.amends),
            ("repeals", draft.repeals), ("source", draft.source),
        ] + draft.tags.map { ("tags", $0) } + draft.amendsAlso.map { ("amends-also", $0) }
            + draft.cites.flatMap { [("cites", $0.id), ("cites", $0.rel)] }
        for (name, value) in fields where value?.contains(where: \.isNewline) == true {
            throw LawEnactError.multilineValue(name)
        }
    }

    // MARK: - 참조와 관계

    /// 관계 집합·출발 규칙 → 참조 해석 → 도착 규칙 → 정리본 인용 금지. 해석한 인용 도착을 돌려준다.
    func checkReferences(_ draft: LawDraft, type: LawRecordType) throws -> [(LawCite, LawResolvedReference)] {
        var resolved: [(LawCite, LawResolvedReference)] = []
        for cite in draft.cites {
            guard let relation = LawRelation(rawValue: cite.rel) else { throw LawEnactError.relationNotAllowed(cite.rel) }
            guard relation.allowsSource(type: type.rawValue, origin: draft.origin, amendsOrRepeals: Self.amendsOrRepeals(draft)) else {
                throw LawEnactError.relationSourceRefused(rel: cite.rel, type: type.rawValue)
            }
            guard let target = resolve(cite.id) else { throw LawEnactError.unresolvedReference(cite.id) }
            guard relation.allowsTarget(type: target.type, isPredecessor: target.scope == .predecessor) else {
                throw LawEnactError.relationTargetRefused(rel: cite.rel, target: cite.id)
            }
            if target.origin == LawOrigin.dream.rawValue,
               relation == .testifies || relation == .finds || type == .evidence {
                throw LawEnactError.dreamCitationRefused(cite.id)
            }
            resolved.append((cite, target))
        }
        for ref in [draft.amends, draft.repeals].compactMap({ $0 }) + draft.amendsAlso where resolve(ref) == nil {
            throw LawEnactError.unresolvedReference(ref)
        }
        return resolved
    }

    static func amendsOrRepeals(_ draft: LawDraft) -> Bool {
        draft.amends != nil || !draft.amendsAlso.isEmpty || draft.repeals != nil
    }

    func checkOrigin(_ draft: LawDraft) throws {
        if draft.origin == LawOrigin.migration.rawValue,
           !draft.cites.contains(where: { $0.rel == LawRelation.migratedFrom.rawValue }) {
            throw LawEnactError.migrationRequiresMigratedFrom
        }
    }

    // MARK: - 화자

    func resolvedSpeaker(
        _ draft: LawDraft, type: LawRecordType, actor: LawActor, head: LawHeadFieldBlock,
        resolved: [(LawCite, LawResolvedReference)]
    ) throws -> String? {
        if type == .evidence {
            // 세션에서 소환한 증거(머리 칸 session) 또는 user 화자 주장은 증언 확인을 거친다.
            let session = head["session"]
            guard session != nil || draft.speaker == LawSpeaker.user.rawValue else {
                return draft.speaker ?? LawSpeaker.external.rawValue
            }
            guard let verifier = context.testimony else { throw LawEnactError.testimonyUnavailable }
            guard !draft.exhibits.isEmpty else { throw LawEnactError.testimonyMismatch }
            let quotes = draft.exhibits.map { sha in
                LawExhibitQuote(sha256: sha, text: (try? Data(contentsOf: store.exhibitURL(sha256: sha)))
                    .flatMap { String(data: $0, encoding: .utf8) })
            }
            let request = LawTestimonyRequest(
                session: session, utteranceAt: head["utterance-at"], runtime: head["runtime"],
                device: head["device"], quotes: quotes)
            guard let witnessed = try verifier.speaker(for: request) else { throw LawEnactError.testimonyMismatch }
            if let claimed = draft.speaker, claimed != witnessed.rawValue { throw LawEnactError.testimonyMismatch }
            return witnessed.rawValue
        }
        let speaker = draft.speaker ?? {
            switch actor.kind {
            case .agent: return LawSpeaker.agent.rawValue
            case .human: return LawSpeaker.user.rawValue
            case .app: return nil
            }
        }()
        // 사람이 직접 공포한 기록은 speaker: user 다. 그 밖의 speaker: user 는 증언이 있어야 한다.
        // 승격본이라고 주장하는 증거는 승격 영수증이 확인될 때만 증언이 된다(`LawPromotionWitness`).
        if speaker == LawSpeaker.user.rawValue, actor.kind != .human {
            let testified = resolved.contains { cite, target in
                cite.rel == LawRelation.testifies.rawValue
                    && target.type == LawRecordType.evidence.rawValue
                    && target.speaker == LawSpeaker.user.rawValue
                    && promotionAccepted(target.id)
            }
            guard testified else { throw LawEnactError.speakerUserRequiresTestimony }
        }
        return speaker
    }

    func promotionAccepted(_ id: String) -> Bool {
        switch context.promotions?.status(of: id) ?? .notClaimed {
        case .notClaimed, .genuine: return true
        case .unproven: return false
        }
    }
}
