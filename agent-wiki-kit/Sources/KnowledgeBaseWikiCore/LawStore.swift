import Foundation
import WikiLedgerKit

/// 원장에 놓인 ledger 3 기록(저장된 id 와 기록).
public struct LawStoredRecord: Sendable, Equatable {
    public let id: String
    public let record: LawRecord

    public init(id: String, record: LawRecord) {
        self.id = id
        self.record = record
    }
}

/// ledger 3 원장 저장소. 쓰기 연산은 공포(`enact`)뿐이다 — 개정·폐지·원상회복도 공포로 한다.
/// 형식(직렬화·파싱)은 WikiLedgerKit 이 정본이다. 옛 `LedgerStore`(ledger 1·2)와 따로 둔다.
/// 근거: docs/business-rules.md "agent-law(ledger 3)", docs/standards.md "agent-law (ledger 3)", 결정 0007.
public struct LawStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    var objectsDir: URL { root.appendingPathComponent("objects") }
    var exhibitsDir: URL { root.appendingPathComponent("exhibits") }

    /// `<원장 루트>/objects/YYYY/MM/<id>.md`(공포일의 UTC 연·월).
    public func objectURL(id: String, promulgated: Date) -> URL {
        let utc = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let components = Calendar(identifier: .gregorian).dateComponents(in: utc, from: promulgated)
        return objectsDir
            .appendingPathComponent(String(format: "%04d", components.year ?? 0))
            .appendingPathComponent(String(format: "%02d", components.month ?? 0))
            .appendingPathComponent("\(id).md")
    }

    /// `<원장 루트>/exhibits/<sha256 앞 2자>/<sha256>`.
    public func exhibitURL(sha256: String) -> URL {
        exhibitsDir.appendingPathComponent(String(sha256.prefix(2))).appendingPathComponent(sha256)
    }

    // MARK: - 공포 (유일한 쓰기 연산)

    /// 공포. 규칙을 모두 통과하면 `objects/YYYY/MM/<id>.md` 에 덮어쓰기 없이 쓴다.
    /// 같은 id 파일이 있으면 바이트가 같을 때만 성공(멱등), 다르면 `duplicateID`.
    @discardableResult
    public func enact(_ draft: LawDraft, now: Date = Date(), context: LawEnactContext = LawEnactContext()) throws
        -> LawStoredRecord {
        let existing = scan()
        var context = context
        if context.promotions == nil { context.promotions = LawPromotionWitness(records: existing) }
        let record = try LawEnactValidator(
            store: self, context: context, sameLedger: LawSameLedgerResolver(records: existing)
        ).validatedRecord(draft, promulgated: LawTime.truncatedToMilliseconds(now))
        let id = record.contentID()
        let url = objectURL(id: id, promulgated: record.promulgated)
        let payload = Data(record.serialize(id: id).utf8)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let present = try? Data(contentsOf: url) {
            guard present == payload else { throw LawEnactError.duplicateID(id) }
            return LawStoredRecord(id: id, record: record)
        }
        do {
            try payload.write(to: url, options: [.withoutOverwriting])
        } catch {
            // 경합으로 그 사이 같은 id 가 쓰였으면 바이트 비교로 멱등 판정.
            if let present = try? Data(contentsOf: url) {
                guard present == payload else { throw LawEnactError.duplicateID(id) }
                return LawStoredRecord(id: id, record: record)
            }
            throw error
        }
        return LawStoredRecord(id: id, record: record)
    }

    // MARK: - 원상회복

    /// `restore <batch>` — 묶음의 기록마다 새 기록을 공포한다. 개정이었으면 이전 판을 다시 공포(`amends`),
    /// 신규였으면 폐지(`repeals`). 파일은 지우지 않는다. 새 기록들은 새 묶음 id 하나를 공유한다.
    /// - Parameter perRuling: 결정에 따른 원상회복이면 그 결정(`ruling`) id — `per-ruling` 으로 인용한다.
    @discardableResult
    public func restore(
        batch: String, actor: LawActor, now: Date = Date(), context: LawEnactContext = LawEnactContext(),
        perRuling: String? = nil
    ) throws -> [LawStoredRecord] {
        let records = scan()
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let targets = records.filter { $0.record.batch == batch }
        guard !targets.isEmpty else { throw LawEnactError.batchNotFound(batch) }
        let restoreBatch = LedgerID.generate(now: now)
        let rulingCite = perRuling.map { [LawCite(id: $0, rel: LawRelation.perRuling.rawValue)] } ?? []
        var enacted: [LawStoredRecord] = []
        for target in targets {
            if let previousID = target.record.amends, let previous = byID[previousID]?.record {
                enacted.append(try enact(LawDraft(
                    actor: actor, speaker: previous.speaker, title: previous.title,
                    type: previous.type ?? LawRecordType.record.rawValue, origin: previous.origin,
                    batch: restoreBatch, tags: previous.tags, cites: previous.cites + rulingCite,
                    exhibits: previous.exhibits, amends: target.id, source: previous.source,
                    body: previous.body), now: now, context: context))
            } else {
                enacted.append(try enact(LawDraft(
                    actor: actor, title: target.record.title.map { "폐지: \($0)" },
                    type: target.record.type ?? LawRecordType.record.rawValue, batch: restoreBatch,
                    cites: rulingCite, repeals: target.id, body: "restore \(batch)"), now: now, context: context))
            }
        }
        return enacted
    }

    // MARK: - 조회

    /// 파싱되는 ledger 3 기록 전부(공포일, id 순). id 재해시는 검사하지 않는다 — 무결성은 `audit()` 로만 본다.
    public func scan() -> [LawStoredRecord] {
        objectFiles().compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let parsed = LawRecordParser.parse(text) else { return nil }
            return LawStoredRecord(id: parsed.storedID, record: parsed.record)
        }.sorted { ($0.record.promulgated, $0.id) < ($1.record.promulgated, $1.id) }
    }

    func objectFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "md" { urls.append(url) }
        return urls.sorted { $0.path < $1.path }
    }
}
