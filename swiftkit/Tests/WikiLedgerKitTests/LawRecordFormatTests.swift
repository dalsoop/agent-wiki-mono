import CryptoKit
import Foundation
import Testing
@testable import WikiLedgerKit

/// ledger 3 형식 시험 — 근거: docs/business-rules.md "기록 정체성과 표기"·"본문 머리 칸"·"관계".
@Suite("ledger 3 기록 형식")
struct LawRecordFormatTests {

    static let citedID = String(repeating: "a", count: 64)
    static let exhibitSHA = String(repeating: "e", count: 64)

    static func sample(cost: LawCost? = nil, model: String? = "claude-opus-5-5") -> LawRecord {
        LawRecord(
            promulgated: LawTime.parse("2026-10-04T01:02:03.456Z")!,
            author: "agent:claude@macbook",
            authorKind: "agent",
            device: "macbook",
            runtime: "claude-code",
            runtimeVersion: "2.1.0",
            model: model,
            effort: "high",
            speaker: "agent",
            title: "제목",
            type: "record",
            batch: "b1",
            tags: ["a", "b"],
            cites: [LawCite(id: citedID, rel: "cites")],
            exhibits: [exhibitSHA],
            unknownFields: ["x-extra: 1"],
            body: "본문\n",
            cost: cost)
    }

    static let goldenCore = """
        ledger: 3
        promulgated: 2026-10-04T01:02:03.456Z
        author: agent:claude@macbook
        author-kind: agent
        device: macbook
        runtime: claude-code
        runtime-version: 2.1.0
        model: claude-opus-5-5
        effort: high
        speaker: agent
        title: 제목
        type: record
        batch: b1
        tags: [a, b]
        cites: \(citedID) cites
        exhibit: \(exhibitSHA)
        x-extra: 1
        ---
        본문

        """

    static func independentSHA(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    @Test("canonicalCore 골든 바이트")
    func goldenCanonicalCore() {
        #expect(Self.sample().canonicalCore() == Self.goldenCore)
    }

    @Test("직렬화 골든 바이트 — 머리 필드 순서 ledger,id,promulgated,author,sha256,…,cost")
    func goldenSerialization() {
        let cost = LawCost(tokensIn: 10, tokensOut: nil, objectsRead: 3, session: "s1")
        let record = Self.sample(cost: cost)
        let id = Self.independentSHA(Self.goldenCore)
        let bodySHA = Self.independentSHA("본문\n")
        let expected = """
            ---
            ledger: 3
            id: \(id)
            promulgated: 2026-10-04T01:02:03.456Z
            author: agent:claude@macbook
            sha256: \(bodySHA)
            author-kind: agent
            device: macbook
            runtime: claude-code
            runtime-version: 2.1.0
            model: claude-opus-5-5
            effort: high
            speaker: agent
            title: 제목
            type: record
            batch: b1
            tags: [a, b]
            cites: \(Self.citedID) cites
            exhibit: \(Self.exhibitSHA)
            x-extra: 1
            cost: {"tokensIn":10,"objectsRead":3,"session":"s1"}
            ---
            본문

            """
        #expect(record.contentID() == id)
        #expect(record.serialize() == expected)
    }

    @Test("코어 필드 전체 순서")
    func fullCoreOrder() {
        let record = LawRecord(
            promulgated: LawTime.parse("2026-01-01T00:00:00.000Z")!,
            author: "app:dreamer", authorKind: "app", device: "d1",
            runtime: "codex", runtimeVersion: "1", model: "m", effort: "low",
            app: "agent-wiki", appVersion: "9", speaker: "agent",
            title: "t", type: "record", origin: "migration", batch: "b",
            tags: ["x"], cites: [LawCite(id: Self.citedID, rel: "migrated-from")],
            exhibits: [Self.exhibitSHA], amends: "1", amendsAlso: ["2", "3"], repeals: "4",
            source: #"{"path":"p"}"#, unknownFields: ["zz: 1"], body: "b")
        let keys = record.coreLines().map { String($0.split(separator: ":", maxSplits: 1)[0]) }
        #expect(keys == ["ledger", "promulgated", "author", "author-kind", "device", "runtime",
                         "runtime-version", "model", "effort", "app", "app-version", "speaker",
                         "title", "type", "origin", "batch", "tags", "cites", "exhibit", "amends",
                         "amends-also", "amends-also", "repeals", "source", "zz"])
    }

    @Test("cost 는 id 를 바꾸지 않는다")
    func costOutsideCore() {
        let a = Self.sample(cost: nil)
        let b = Self.sample(cost: LawCost(tokensIn: 999, tokensOut: 1, objectsRead: 50, session: "x"))
        #expect(a.contentID() == b.contentID())
        #expect(a.serialize() != b.serialize())
    }

    @Test("모델 기록은 id 를 바꾼다")
    func modelInsideCore() {
        #expect(Self.sample(model: "claude-opus-5-5").contentID()
                != Self.sample(model: "claude-sonnet-5").contentID())
    }

    @Test("파서 왕복 — 바이트 동일, 저장된 id·sha256 보존")
    func parseRoundTrip() throws {
        let record = Self.sample(cost: LawCost(tokensIn: 1, tokensOut: 2, objectsRead: 3, session: "s"))
        let text = record.serialize()
        let parsed = try #require(LawRecordParser.parse(text))
        #expect(parsed.storedID == record.contentID())
        #expect(parsed.storedSHA256 == LawHash.sha256Hex("본문\n"))
        #expect(parsed.record.serialize() == text)
        #expect(parsed.record.contentID() == parsed.storedID)
        #expect(parsed.record.cost == record.cost)
        #expect(parsed.record.unknownFields == ["x-extra: 1"])
    }

    @Test("값 없는 필드는 줄을 쓰지 않는다")
    func omitEmpty() {
        let record = LawRecord(
            promulgated: Date(timeIntervalSince1970: 0), author: "user:yun",
            authorKind: "human", body: "x")
        #expect(record.coreLines() == ["ledger: 3", "promulgated: 1970-01-01T00:00:00.000Z",
                                       "author: user:yun", "author-kind: human"])
    }

    @Test("제목·태그 NFC, 본문은 그대로")
    func nfc() {
        let nfd = "한글".decomposedStringWithCanonicalMapping
        let record = LawRecord(
            promulgated: Date(timeIntervalSince1970: 0), author: "user:yun", title: nfd,
            tags: [nfd], body: nfd).nfcNormalized()
        #expect(record.title == "한글".precomposedStringWithCanonicalMapping)
        #expect(record.tags == ["한글".precomposedStringWithCanonicalMapping])
        #expect(record.body == nfd)
    }

    @Test("ledger 2 파일은 ledger 3 파서가 받지 않는다")
    func rejectsLedger2() {
        let text = "---\nledger: 2\nid: x\npublished: 2026-01-01T00:00:00.000Z\nauthor: a\nsha256: y\n---\nbody"
        #expect(LawRecordParser.parse(text) == nil)
    }

    @Test("해시는 소문자 64자 16진수")
    func hashShape() {
        let h = LawHash.sha256Hex("abc")
        #expect(h == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // MARK: - 머리 칸

    @Test("사실인정 머리 칸 파서")
    func findingHead() throws {
        let body = "subject: person\ncertainty: confirmed\ndomain: dev-workflow\nreason: 근거\n\n본문"
        let head = try LawHeadFields.parse(body: body, type: "finding")
        #expect(head["subject"] == "person")
        #expect(head["reason"] == "근거")
        #expect(head.keys == ["subject", "certainty", "domain", "reason"])
    }

    @Test("허용되지 않은 머리 칸 키 거부")
    func unknownHeadKey() {
        #expect(throws: LawHeadFieldError.self) {
            try LawHeadFields.parse(body: "subject: person\nmood: happy\n\nx", type: "finding")
        }
    }

    @Test("사실인정 reason 비면 거부, 값 집합 밖 거부")
    func findingValues() {
        #expect(throws: LawHeadFieldError.self) {
            try LawHeadFields.parse(
                body: "subject: person\ncertainty: confirmed\ndomain: dev-workflow\nreason: \n\nx",
                type: "finding")
        }
        #expect(throws: LawHeadFieldError.self) {
            try LawHeadFields.parse(
                body: "subject: alien\ncertainty: confirmed\ndomain: dev-workflow\nreason: r\n\nx",
                type: "finding")
        }
    }

    @Test("머리 칸이 없는 유형은 본문을 그대로 둔다")
    func recordHasNoHead() throws {
        let head = try LawHeadFields.parse(body: "subject: person\n\nx", type: "record")
        #expect(head.keys.isEmpty)
    }

    // MARK: - 어휘·관계

    @Test("유형 집합: 지식 3·처리 11")
    func typeSets() {
        #expect(LawRecordType.knowledgeTypes.map(\.rawValue).sorted() == ["article", "judgment", "record"])
        #expect(LawRecordType.processTypes.count == 11)
        #expect(LawRecordType.processTypes.contains(.promotionReceipt))
        #expect(LawRecordType.knowledgeTypes.isDisjoint(with: LawRecordType.processTypes))
    }

    @Test("관계 출발·도착 규칙")
    func relationRules() {
        #expect(LawRelation(rawValue: "rolls-back") == nil)
        #expect(LawRelation.finds.allowsSource(type: "finding", origin: nil, amendsOrRepeals: false))
        #expect(!LawRelation.finds.allowsSource(type: "record", origin: nil, amendsOrRepeals: false))
        #expect(LawRelation.finds.allowsTarget(type: "record", isPredecessor: false))
        #expect(!LawRelation.finds.allowsTarget(type: "evidence", isPredecessor: false))
        #expect(LawRelation.testifies.allowsTarget(type: "evidence", isPredecessor: false))
        #expect(!LawRelation.testifies.allowsTarget(type: "record", isPredecessor: false))
        #expect(LawRelation.migratedFrom.allowsSource(type: "record", origin: "migration", amendsOrRepeals: false))
        #expect(!LawRelation.migratedFrom.allowsSource(type: "record", origin: nil, amendsOrRepeals: false))
        #expect(LawRelation.migratedFrom.allowsTarget(type: "concept", isPredecessor: true))
        #expect(!LawRelation.migratedFrom.allowsTarget(type: "record", isPredecessor: false))
        #expect(LawRelation.perRuling.allowsSource(type: "record", origin: nil, amendsOrRepeals: true))
        #expect(!LawRelation.perRuling.allowsSource(type: "record", origin: nil, amendsOrRepeals: false))
        #expect(LawRelation.hears.allowsTarget(type: "appeal", isPredecessor: false))
        #expect(!LawRelation.hears.allowsTarget(type: "record", isPredecessor: false))
        #expect(LawRelation.cites.allowsSource(type: "contents", origin: "dream", amendsOrRepeals: false))
    }
}
