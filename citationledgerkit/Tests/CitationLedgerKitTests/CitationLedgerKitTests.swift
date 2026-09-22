import Foundation
import Testing

@testable import CitationLedgerKit

/// 데모 conformer — 두 앱의 실제 객체가 이렇게 conform 한다.
private struct DemoObject: CitationLedgerObject {
    var published: Date
    var author: String
    var body: String
    func canonicalCore() -> String {
        "---\npublished: \(CitationLedger.string(from: published))\nauthor: \(author)\n---\n\(body)"
    }
}

@Suite struct ContentAddressTests {
    @Test func sha256Reproducible() {
        let a = CitationLedger.sha256Hex("hello")
        let b = CitationLedger.sha256Hex("hello")
        #expect(a == b)
        #expect(a.count == 64)
        #expect(a == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    @Test func contentIDChangesWithContent() {
        let base = DemoObject(published: Date(timeIntervalSince1970: 1000), author: "a", body: "x")
        let same = DemoObject(published: Date(timeIntervalSince1970: 1000), author: "a", body: "x")
        let diff = DemoObject(published: Date(timeIntervalSince1970: 1000), author: "a", body: "y")
        #expect(base.contentID == same.contentID)  // 같은 내용 = 같은 id (dedup)
        #expect(base.contentID != diff.contentID)  // 내용 바뀌면 다른 id
        #expect(base.contentID.count == 64)
    }

    @Test func verifySelf() {
        let o = DemoObject(published: Date(timeIntervalSince1970: 1000), author: "a", body: "x")
        #expect(o.verifyContentID(o.contentID))
        #expect(!o.verifyContentID("deadbeef"))
    }
}

@Suite struct TimeTests {
    @Test func msRoundTripStable() {
        // sub-ms Date 를 직렬화→파싱→직렬화 했을 때 문자열이 안정적이어야 한다.
        let now = Date()
        let s1 = CitationLedger.string(from: now)
        let parsed = CitationLedger.date(from: s1)!
        let s2 = CitationLedger.string(from: parsed)
        #expect(s1 == s2)
    }

    @Test func parsesBothPrecisions() {
        #expect(CitationLedger.date(from: "2026-07-22T05:03:22.000Z") != nil)  // ms
        #expect(CitationLedger.date(from: "2026-07-22T05:03:22Z") != nil)      // 초(v1 폴백)
    }
}

@Suite struct UUIDv7Tests {
    @Test func timeOrdered() {
        let a = CitationLedger.uuidV7(now: Date(timeIntervalSince1970: 1000))
        let b = CitationLedger.uuidV7(now: Date(timeIntervalSince1970: 2000))
        #expect(a < b)
        #expect(a.count == 36)  // 8-4-4-4-12
    }
}

@Suite struct LedgerLookupTests {
    // 임시 원장 디렉터리에 objects/YYYY/MM/<id>.md 를 만들고 조회.
    private func makeLedger(ids: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clk-lookup-\(UUID().uuidString)")
        let objects = root.appendingPathComponent("objects/2026/07")
        try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)
        for id in ids {
            try "---\nid: \(id)\n---\nbody".write(
                to: objects.appendingPathComponent("\(id).md"), atomically: true, encoding: .utf8)
        }
        return root
    }

    @Test func findsExistingAndMissing() throws {
        let root = try makeLedger(ids: ["abc123", "def456"])
        defer { try? FileManager.default.removeItem(at: root) }
        let objectsDir = root.appendingPathComponent("objects")
        #expect(LedgerLookup.exists(id: "abc123", inObjectsDir: objectsDir))
        #expect(LedgerLookup.exists(id: "def456", inObjectsDir: objectsDir))
        #expect(!LedgerLookup.exists(id: "nope999", inObjectsDir: objectsDir))
        // 접두어 부분일치는 안 침 — 정확한 content-address 만.
        #expect(!LedgerLookup.exists(id: "abc", inObjectsDir: objectsDir))
        #expect(LedgerLookup.objectURL(id: "abc123", inObjectsDir: objectsDir) != nil)
    }

    // frontmatter 에 supersedes/retracts 를 넣은 객체 파일 추가.
    private func addObject(_ id: String, extra: String, in objectsDir: URL) throws {
        try "---\nid: \(id)\n\(extra)---\nbody".write(
            to: objectsDir.appendingPathComponent("2026/07/\(id).md"),
            atomically: true, encoding: .utf8)
    }

    @Test func statusReflectsRetractAndSupersede() throws {
        let root = try makeLedger(ids: ["decA", "decB", "decC"])
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("objects")
        // decA 는 그대로 head. decB 는 개정됨. decC 는 철회됨.
        try addObject("rev1", extra: "supersedes: decB\n", in: dir)
        try addObject("ret1", extra: "retracts: decC\n", in: dir)
        #expect(LedgerLookup.status(id: "decA", inObjectsDir: dir) == .head)
        #expect(LedgerLookup.status(id: "decB", inObjectsDir: dir) == .superseded(by: "rev1"))
        #expect(LedgerLookup.status(id: "decC", inObjectsDir: dir) == .retracted(by: "ret1"))
        #expect(LedgerLookup.status(id: "nope", inObjectsDir: dir) == .missing)
    }
}

@Suite struct CitationActorTests {
    @Test func envOverridesFile() throws {
        // 신원 파일이 있어도 CITATION_ACTOR env 가 최우선.
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("clk-actor-\(UUID().uuidString)")
        let cfg = home.appendingPathComponent(".config/citation-ledger")
        try FileManager.default.createDirectory(at: cfg, withIntermediateDirectories: true)
        try "agent:file@host".write(to: cfg.appendingPathComponent("actor"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(CitationActor.resolve(environment: ["CITATION_ACTOR": "agent:env@host"], home: home)
            == "agent:env@host")
        // env 없으면 파일 값.
        #expect(CitationActor.resolve(environment: [:], home: home) == "agent:file@host")
    }

    @Test func fallbackWhenUnset() {
        // 파일 없는 임시 home + env 없음 → user@host 폴백.
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("clk-actor-empty-\(UUID().uuidString)")
        let actor = CitationActor.resolve(environment: ["USER": "alice"], home: empty)
        #expect(actor.hasPrefix("alice@"))
    }
}
