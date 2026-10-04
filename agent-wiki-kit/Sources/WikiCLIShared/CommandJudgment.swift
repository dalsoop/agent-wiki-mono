import Foundation
import KnowledgeBaseWikiCore
import WikiLedgerKit

// judgment register|amend|repeal|list|show — 판결 등록. 공유 원장(층 remoteShared 인 ledger 3 원장)에 `registration`
// 기록을 공포한다. 판결 번호는 처음 등록 기록 id 의 앞 8자리이고 개정해도 바뀌지 않는다.
// 상태·경로 변경은 개정(`judgment amend`), 폐지는 `judgment repeal` 이다 — 일반 `amend`·`repeal` 은 판결 등록을 다루지 못한다(`LawEnactPath`).
// 확정(`status: confirmed`)은 사용자 발화 증언(`--testimony <speaker: user 증거 id>`)이 있어야 하고, 확정 판결의 개정·폐지는
// 대법원 결정(`court decide`)의 조치로만 된다 — 판정은 `LawEnactPath.checkRegistration` 한 곳.
// 저장소 판결 본문은 받지 않는다(본문은 머리 칸만).
// 근거: docs/contracts.md "agent-law 명령 (ledger 3)" 판결 행, docs/business-rules.md "판결 등록"·"본문 머리 칸"·"유형".

let judgmentUsage = """
사용법: judgment register --repo <r> --title <t> [--status provisional|confirmed] [--testimony <증거 id>] [--path <p>]
                          [--batch <id>] [모델 기록 옵션] [--json]
        judgment amend <번호> [--status provisional|confirmed] [--testimony <증거 id>] [--path <p>] [--title <t>]
                       [--batch <id>] [모델 기록 옵션] [--json]
        judgment repeal <번호> [--reason <r>] [--batch <id>] [모델 기록 옵션] [--json]
        judgment list [--repo <r>] [--json]
        judgment show <번호> [--json]
"""

public enum JudgmentRegistryError: Error, Equatable, CustomStringConvertible {
    case notSharedLedger(String)
    case noSharedLedger(String)
    case invalidValue(key: String, value: String)
    case headField(String)
    case notFound(String)
    case ambiguous(String, [String])
    case noInForce(String)

    public var description: String {
        switch self {
        case .notSharedLedger(let world):
            return "판결 등록은 공유 원장(층 remoteShared 인 ledger 3 원장)에만 한다 — \(world) 는 아님. --world agent-law 로 주세요"
        case .noSharedLedger(let world):
            return "\(world) 와 그 상위에 공유 원장(층 remoteShared 인 ledger 3 원장)이 없음"
        case .invalidValue(let key, let value):
            return "--\(key) 값은 한 줄이어야 한다: \(value)"
        case .headField(let message): return message
        case .notFound(let number): return "판결 번호 \(number) 인 등록 기록이 없음"
        case .ambiguous(let number, let numbers):
            return "판결 번호 \(number) 가 여럿에 맞음: \(numbers.joined(separator: ", ")) — 더 길게 주세요"
        case .noInForce(let number): return "판결 \(number) 의 현행판이 없음(폐지됨)"
        }
    }
}

/// 등록 기록 하나의 현행 보기.
public struct JudgmentEntry: Sendable, Equatable, Encodable {
    /// 판결 번호 — 처음 등록 기록 id 의 앞 8자리.
    public let number: String
    /// 처음 등록 기록 id.
    public let firstID: String
    /// 현행판 id.
    public let id: String
    public let repo: String
    public let status: String
    public let path: String?
    public let title: String?
    public let promulgated: String
    /// 연혁 길이(처음 등록이면 1).
    public let revisions: Int

    public var amended: Bool { firstID != id }
}

/// 판결 등록의 순수 부분 — 대상 원장 판정, 초안, 현행 목록, 번호 조회. CLI 와 시험이 같이 쓴다.
public enum JudgmentRegistry {
    public static let numberLength = 8

    /// 등록 대상: 현재 원장이 ledger 3 이고 층이 remoteShared 여야 한다.
    public static func checkRegistrationTarget(worldName: String, catalog: WorldBindingCatalog) throws {
        guard isSharedLedger(worldName, catalog: catalog) else {
            throw JudgmentRegistryError.notSharedLedger(worldName)
        }
    }

    static func isSharedLedger(_ name: String, catalog: WorldBindingCatalog) -> Bool {
        catalog.isLedgerThree(name) && catalog.resolvedLayer(of: name) == .remoteShared
    }

    /// 조회 대상: 현재 원장 또는 가장 가까운 상위 중 공유 원장.
    public static func sharedLedger(for worldName: String, catalog: WorldBindingCatalog) throws -> BoundWorld {
        for name in [worldName] + catalog.ancestorNames(of: worldName) where isSharedLedger(name, catalog: catalog) {
            if let world = catalog.world(named: name) { return world }
        }
        throw JudgmentRegistryError.noSharedLedger(worldName)
    }

    /// 머리 칸 본문 — `repo`, `status`, `path`(주면). 검증은 `LawHeadFields.parse` 한 곳이다.
    public static func body(repo: String, status: String, path: String?) throws -> String {
        for (key, value) in [("repo", repo), ("status", status), ("path", path ?? "")]
        where value.contains(where: \.isNewline) {
            throw JudgmentRegistryError.invalidValue(key: key, value: value)
        }
        var lines = ["repo: \(repo)", "status: \(status)"]
        if let path { lines.append("path: \(path)") }
        let body = lines.joined(separator: "\n") + "\n"
        do {
            _ = try LawHeadFields.parse(body: body, type: LawRecordType.registration.rawValue)
        } catch {
            throw JudgmentRegistryError.headField("\(error)")
        }
        return body
    }

    /// 등록 초안. `testimony`(사용자 발화 증거 id)를 주면 `testifies` 로 인용한다 — 확정으로 등록하려면 필요하다.
    public static func draft(
        actor: LawActor, repo: String, title: String, status: String?, path: String?, batch: String? = nil,
        testimony: String? = nil
    ) throws -> LawDraft {
        LawDraft(
            actor: actor, title: title, type: LawRecordType.registration.rawValue, batch: batch,
            cites: testimonyCites(testimony),
            body: try body(repo: repo, status: status ?? LawRegistrationStatus.provisional.rawValue, path: path))
    }

    /// 개정 초안 — 현행판을 `amends` 로 대체한다. 비운 칸은 현행판의 값을 그대로 쓴다.
    /// 잠정 → 확정은 `testimony`(사용자 발화 증거 id)가 있어야 하고, 확정 판결의 개정은 거부된다(대법원으로).
    public static func amendDraft(
        actor: LawActor, entry: JudgmentEntry, title: String?, status: String?, path: String?, batch: String? = nil,
        testimony: String? = nil
    ) throws -> LawDraft {
        LawDraft(
            actor: actor, title: title ?? entry.title, type: LawRecordType.registration.rawValue, batch: batch,
            cites: testimonyCites(testimony), amends: entry.id,
            body: try body(repo: entry.repo, status: status ?? entry.status, path: path ?? entry.path))
    }

    /// 폐지 초안 — 현행판을 `repeals` 한다. 본문은 이유(비어도 된다). 확정 판결의 폐지는 거부된다(대법원으로).
    public static func repealDraft(
        actor: LawActor, entry: JudgmentEntry, reason: String?, batch: String? = nil
    ) -> LawDraft {
        LawDraft(
            actor: actor, title: "폐지: \(entry.title ?? entry.number)", type: LawRecordType.registration.rawValue,
            batch: batch, repeals: entry.id, body: reason ?? "")
    }

    static func testimonyCites(_ testimony: String?) -> [LawCite] {
        testimony.map { [LawCite(id: $0, rel: LawRelation.testifies.rawValue)] } ?? []
    }

    public static func number(of id: String) -> String { String(id.prefix(numberLength)) }

    /// 현행 등록 기록들(번호 순서는 처음 등록의 공포 순). `repo` 를 주면 그 저장소만.
    public static func entries(records: [LawStoredRecord], repo: String? = nil) -> [JudgmentEntry] {
        let view = LawLedgerView(records: records)
        let entries = view.inForce
            .filter { $0.record.type == LawRecordType.registration.rawValue }
            .compactMap { entry(head: $0, view: view) }
            .filter { repo == nil || $0.repo == repo }
        return entries.sorted { ($0.firstPromulgated(view), $0.firstID) < ($1.firstPromulgated(view), $1.firstID) }
    }

    /// 번호(앞 8자리, 4자 이상의 접두도 받음)로 현행판을 찾는다. 현행판·처음 등록 id 어느 쪽 접두도 받는다.
    public static func find(_ token: String, records: [LawStoredRecord]) throws -> JudgmentEntry {
        let key = token.trimmingCharacters(in: .whitespaces).lowercased()
        guard key.count >= 4 else { throw JudgmentRegistryError.notFound(token) }
        let view = LawLedgerView(records: records)
        let registrations = view.records.filter { $0.record.type == LawRecordType.registration.rawValue }
        // 접두에 맞는 기록 → 그 처음 등록 id.
        let roots = Set(registrations.filter { $0.id.hasPrefix(key) }.compactMap { view.history(of: $0.id).last?.id })
        guard !roots.isEmpty else { throw JudgmentRegistryError.notFound(token) }
        guard roots.count == 1, let root = roots.first else {
            throw JudgmentRegistryError.ambiguous(token, roots.map { number(of: $0) }.sorted())
        }
        let heads = registrations.filter { view.isInForce($0.id) && view.history(of: $0.id).last?.id == root }
        guard let head = heads.last, let found = entry(head: head, view: view) else {
            throw JudgmentRegistryError.noInForce(number(of: root))
        }
        return found
    }

    static func entry(head: LawStoredRecord, view: LawLedgerView) -> JudgmentEntry? {
        let chain = view.history(of: head.id)
        guard let first = chain.last,
              let fields = try? LawHeadFields.parse(body: head.record.body, type: head.record.type),
              let repo = fields["repo"], let status = fields["status"]
        else { return nil }
        let path = fields["path"].flatMap { $0.isEmpty ? nil : $0 }
        return JudgmentEntry(
            number: number(of: first.id), firstID: first.id, id: head.id, repo: repo, status: status,
            path: path, title: head.record.title, promulgated: LawTime.format(head.record.promulgated),
            revisions: chain.count)
    }
}

private extension JudgmentEntry {
    func firstPromulgated(_ view: LawLedgerView) -> String {
        view.history(of: id).last.map { LawTime.format($0.record.promulgated) } ?? promulgated
    }
}

// MARK: - 명령

public func runJudgment(context: LawCommandContext, arguments: [String]) {
    let sub = arguments.dropFirst().first ?? ""
    switch sub {
    case "register": runJudgmentRegister(context: context, arguments: arguments)
    case "amend": runJudgmentAmend(context: context, arguments: arguments)
    case "repeal": runJudgmentRepeal(context: context, arguments: arguments)
    case "list": runJudgmentList(context: context, arguments: arguments)
    case "show": runJudgmentShow(context: context, arguments: arguments)
    default: usageFail(judgmentUsage)
    }
}

func runJudgmentRegister(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(
        arguments, skip: 2,
        valued: Set(["--repo", "--title", "--status", "--path", "--batch", "--testimony"]).union(LawOptions.modelOptions),
        usage: judgmentUsage)
    guard options.positionals.isEmpty, let repo = options.value("--repo"), let title = options.value("--title")
    else { usageFail(judgmentUsage) }
    let world = context.requireWorld()
    do {
        try JudgmentRegistry.checkRegistrationTarget(worldName: world.name, catalog: context.catalog)
    } catch {
        lawFail(error)
    }
    let index = context.scopeIndex()
    let draft: LawDraft
    do {
        draft = try JudgmentRegistry.draft(
            actor: context.actor(explicit: options.modelRecord), repo: repo, title: title,
            status: options.value("--status"), path: options.value("--path"),
            batch: options.value("--batch") ?? context.environment["MEMO_LEDGER_BATCH"],
            testimony: judgmentTestimony(options, index: index))
    } catch {
        lawFail(error)
    }
    let stored = enactLaw(draft, context: context, index: index, path: .judgment)
    let number = JudgmentRegistry.number(of: stored.id)
    if options.has("--json") {
        struct Envelope: Encodable { let ok: Bool; let result: Result }
        struct Result: Encodable { let ids: [String]; let number: String }
        printJSON(Envelope(ok: true, result: Result(ids: [stored.id], number: number)))
    } else {
        print(stored.id) // allow:debug — 공포류 표준 출력은 id 한 줄
        FileHandle.standardError.write(Data("판결 번호: \(number)\n".utf8))
    }
}

func runJudgmentAmend(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(
        arguments, skip: 2,
        valued: Set(["--title", "--status", "--path", "--batch", "--testimony"]).union(LawOptions.modelOptions),
        usage: judgmentUsage)
    guard options.positionals.count == 1,
          options.value("--status") != nil || options.value("--path") != nil || options.value("--title") != nil
    else { usageFail(judgmentUsage) }
    let world = context.requireWorld()
    let index = context.scopeIndex()
    let draft: LawDraft
    do {
        try JudgmentRegistry.checkRegistrationTarget(worldName: world.name, catalog: context.catalog)
        let entry = try JudgmentRegistry.find(options.positionals[0], records: context.lawTarget().store.scan())
        draft = try JudgmentRegistry.amendDraft(
            actor: context.actor(explicit: options.modelRecord), entry: entry, title: options.value("--title"),
            status: options.value("--status"), path: options.value("--path"),
            batch: options.value("--batch") ?? context.environment["MEMO_LEDGER_BATCH"],
            testimony: judgmentTestimony(options, index: index))
    } catch {
        lawFail(error)
    }
    let stored = enactLaw(draft, context: context, index: index, path: .judgment)
    printEnacted([stored.id], asJSON: options.has("--json"))
}

/// judgment repeal <번호> [--reason <r>] — 판결 등록 폐지(`judgment` 경로). 확정 판결은 거부된다(대법원 결정의 조치로만).
func runJudgmentRepeal(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(
        arguments, skip: 2, valued: Set(["--reason", "--batch"]).union(LawOptions.modelOptions), usage: judgmentUsage)
    guard options.positionals.count == 1 else { usageFail(judgmentUsage) }
    let world = context.requireWorld()
    let draft: LawDraft
    do {
        try JudgmentRegistry.checkRegistrationTarget(worldName: world.name, catalog: context.catalog)
        let entry = try JudgmentRegistry.find(options.positionals[0], records: context.lawTarget().store.scan())
        draft = JudgmentRegistry.repealDraft(
            actor: context.actor(explicit: options.modelRecord), entry: entry, reason: options.value("--reason"),
            batch: options.value("--batch") ?? context.environment["MEMO_LEDGER_BATCH"])
    } catch {
        lawFail(error)
    }
    let stored = enactLaw(draft, context: context, index: context.scopeIndex(), path: .judgment)
    printEnacted([stored.id], asJSON: options.has("--json"))
}

/// `--testimony` 증거 토큰 → 기록 id(없으면 nil).
func judgmentTestimony(_ options: LawOptions, index: LawScopeIndex) -> String? {
    options.value("--testimony").map { resolveLawReferences([$0], index: index)[0] }
}

/// 조회 대상 공유 원장의 기록들.
func judgmentRecords(context: LawCommandContext) -> [LawStoredRecord] {
    do {
        let world = try JudgmentRegistry.sharedLedger(for: context.requireWorld().name, catalog: context.catalog)
        return LawStore(root: URL(fileURLWithPath: world.rootPath)).scan()
    } catch {
        lawFail(error)
    }
}

func runJudgmentList(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, skip: 2, valued: ["--repo"], usage: judgmentUsage)
    guard options.positionals.isEmpty else { usageFail(judgmentUsage) }
    let entries = JudgmentRegistry.entries(records: judgmentRecords(context: context), repo: options.value("--repo"))
    if options.has("--json") {
        struct Envelope: Encodable { let ok: Bool; let result: [JudgmentEntry] }
        printJSON(Envelope(ok: true, result: entries))
        return
    }
    for entry in entries {
        print("\(entry.number)  \(entry.repo)  \(entry.status)  \(entry.title ?? "")") // allow:debug
    }
}

func runJudgmentShow(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, skip: 2, valued: [], usage: judgmentUsage)
    guard options.positionals.count == 1 else { usageFail(judgmentUsage) }
    let entry: JudgmentEntry
    do {
        entry = try JudgmentRegistry.find(options.positionals[0], records: judgmentRecords(context: context))
    } catch {
        lawFail(error)
    }
    let howToAmend = "상태·경로 변경은 개정: judgment amend \(entry.number) [--status provisional|confirmed] [--testimony <증거 id>] [--path <p>] [--title <t>] · 폐지: judgment repeal \(entry.number) [--reason <r>] · 확정 판결의 변경은 대법원(court)"
    if options.has("--json") {
        struct Envelope: Encodable { let ok: Bool; let result: JudgmentEntry; let amend: String }
        printJSON(Envelope(ok: true, result: entry, amend: howToAmend))
        return
    }
    var lines = [
        "판결 번호: \(entry.number)",
        "현행판: \(entry.id)",
    ]
    if entry.amended { lines.append("처음 등록: \(entry.firstID) (개정 \(entry.revisions - 1)회)") }
    lines += [
        "저장소: \(entry.repo)",
        "상태: \(entry.status)",
        "경로: \(entry.path ?? "")",
        "제목: \(entry.title ?? "")",
        "공포일: \(entry.promulgated)",
    ]
    for line in lines { print(line) } // allow:debug
    FileHandle.standardError.write(Data((howToAmend + "\n").utf8))
}
