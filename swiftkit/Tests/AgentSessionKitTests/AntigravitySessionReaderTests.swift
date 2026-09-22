import XCTest
import Foundation
import SQLite3
import SessionKit
@testable import AgentSessionKit

/// Swift 시스템 SQLite3 모듈엔 SQLITE_TRANSIENT 가 노출되지 않아 직접 둔다.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Antigravity 저장소(실측 스키마)를 fixture 로 만들어 리더 규약을 못박는다.
/// blob 은 protobuf 비정형이지만 문자열 run 추출이 계약이므로, fixture 도
/// 원문 UTF-8 + 구분 바이트로 구성한다 — 실측 저장 모양과 동일한 축소판.
final class AntigravitySessionReaderTests: XCTestCase {

    // MARK: - fixture

    final class FixtureDB {
        let handle: OpaquePointer?

        init(path: String) throws {
            var h: OpaquePointer?
            guard sqlite3_open_v2(path, &h, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let h else {
                fatalError("fixture db open 실패: \(path)")
            }
            handle = h
        }

        deinit { sqlite3_close(handle) }

        func exec(_ sql: String) {
            var err: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, sql, nil, nil, &err) == SQLITE_OK else {
                fatalError("fixture exec 실패: \(err.map { String(cString: $0) } ?? "?") — \(sql)")
            }
        }

        /// 파라미터는 [text, int, blob, nil] 순서대로 순회하며 bind 한다.
        func run(_ sql: String, _ params: [Param]) {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
                fatalError("fixture prepare 실패: \(sql)")
            }
            defer { sqlite3_finalize(stmt) }
            for (i, p) in params.enumerated() {
                let idx = Int32(i + 1)
                switch p {
                case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
                case .int(let v): sqlite3_bind_int64(stmt, idx, v)
                case .blob(let d): d.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32($0.count), SQLITE_TRANSIENT) }
                case .null: sqlite3_bind_null(stmt, idx)
                }
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                fatalError("fixture step 실패: \(sql)")
            }
        }

        enum Param { case text(String); case int(Int64); case blob(Data); case null }
    }

    private func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    /// 테스트 전체에서 쓰는 축소 Antigravity 저장소.
    struct AGFixture {
        let root: String
        let reader: AntigravitySessionReader
        static let liveA = "aaaa1111-2222-3333-4444-555566667777"
        static let liveB = "aaaa1111-9999-3333-4444-555566667777"
        static let killed = "dddd4444-1111-3333-4444-555566667777"
        static let notitle = "eeee5555-1111-3333-4444-555566667777"
        static let noinput = "ffff6666-1111-3333-4444-555566667777"

        var refA: SessionRef {
            SessionRef(tool: .agy, id: Self.liveA, cwd: "", title: nil, lastActive: .now,
                       path: root + "/conversations/" + Self.liveA + ".db", messageCount: 0)
        }
    }

    private func makeAGFixture() throws -> AGFixture {
        let root = NSTemporaryDirectory() + "ag-reader-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root + "/conversations", withIntermediateDirectories: true)

        let summaries = try FixtureDB(path: root + "/conversation_summaries.db")
        summaries.exec("""
            CREATE TABLE conversation_summaries (
                conversation_id TEXT PRIMARY KEY, title TEXT, preview TEXT, step_count INTEGER,
                last_user_input_time TEXT, last_modified_time TEXT, workspace_uris TEXT, killed INTEGER)
            """)
        func summary(_ id: String, title: String?, preview: String?, stepCount: Int64,
                     input: String, modified: String, uris: String, killed: Int64) {
            summaries.run(
                "INSERT INTO conversation_summaries VALUES (?,?,?,?,?,?,?,?)",
                [.text(id), title.map(FixtureDB.Param.text) ?? .null, preview.map(FixtureDB.Param.text) ?? .null,
                 .int(stepCount), .text(input), .text(modified), .text(uris), .int(killed)]
            )
        }
        summary(AGFixture.liveA, title: "Fix tests", preview: "첫 프롬프트", stepCount: 3,
                input: "2026-09-01 12:47:23.036224+00:00", modified: "2026-09-01 12:00:00.000000+00:00",
                uris: "[\"file:///Users/test/proj\"]", killed: 0)
        summary(AGFixture.liveB, title: "Second", preview: "둘째", stepCount: 1,
                input: "2026-08-30 09:00:00.000000+00:00", modified: "2026-08-30 08:00:00.000000+00:00",
                uris: "[\"file:///Users/test/other\"]", killed: 0)
        summary(AGFixture.killed, title: "Killed", preview: "죽은 세션", stepCount: 9,
                input: "2026-08-31 09:00:00.000000+00:00", modified: "2026-08-31 09:00:00.000000+00:00",
                uris: "[]", killed: 1)
        summary(AGFixture.notitle, title: "", preview: "미리보기 프롬프트", stepCount: 2,
                input: "2026-08-28 09:00:00.000000+00:00", modified: "2026-08-28 08:00:00.000000+00:00",
                uris: "[\"file:///Users/test/proj\"]", killed: 0)
        summary(AGFixture.noinput, title: "No input", preview: "입력 없음", stepCount: 0,
                input: "0001-01-01 00:00:00+00:00", modified: "2026-08-20 10:00:00.000000+00:00",
                uris: "[]", killed: 0)

        // live-a 전사본 — step_type 실측 지도(14/15/132/101/999)를 축소 재현.
        let transcript = try FixtureDB(path: root + "/conversations/\(AGFixture.liveA).db")
        transcript.exec("CREATE TABLE steps (idx INTEGER, step_type INTEGER, metadata BLOB, step_payload BLOB)")
        let utf8: (String) -> Data = { Data($0.utf8) }
        let user = utf8("\n안녕하세요 세션 테스트입니다\n") + [0x00] + utf8("\"안녕하세요 세션 테스트입니다\"")
        let agent = utf8("작업을 완료했습니다. 빌드와 테스트를 모두 통과했습니다.")
        let toolMeta = utf8("EditFile") + [0x00]
            + utf8(#"{"AbsolutePath":"/tmp/FixtureProject/Sources/App.swift","command":"swift test","toolSummary":"Ran 2 tests"}"#)
        let toolPayload = utf8("call_abc123def456")
        transcript.run("INSERT INTO steps VALUES (?,?,?,?)", [.int(0), .int(14), .null, .blob(user)])
        transcript.run("INSERT INTO steps VALUES (?,?,?,?)", [.int(1), .int(15), .null, .blob(agent)])
        transcript.run("INSERT INTO steps VALUES (?,?,?,?)", [.int(2), .int(132), .blob(toolMeta), .blob(toolPayload)])
        transcript.run("INSERT INTO steps VALUES (?,?,?,?)", [.int(3), .int(101), .null, .blob(utf8("노이즈 단계"))])
        transcript.run("INSERT INTO steps VALUES (?,?,?,?)", [.int(4), .int(999), .null, .blob(utf8("미지 타입"))])

        return AGFixture(root: root, reader: AntigravitySessionReader(root: root))
    }

    override func tearDown() {
        super.tearDown()
        if let root = storedFixture?.root {
            do { try FileManager.default.removeItem(atPath: root) }
            catch { fputs("fixture cleanup 실패: \(error)\n", stderr) }
        }
        storedFixture = nil
    }

    private var storedFixture: AGFixture?

    private func fixture() throws -> AGFixture {
        if let storedFixture { return storedFixture }
        let f = try makeAGFixture()
        storedFixture = f
        return f
    }

    // MARK: - discover

    func testDiscoverExcludesKilledAndMapsFields() throws {
        let f = try fixture()
        let refs = f.reader.discover()
        XCTAssertEqual(refs.map({ $0.id }), [AGFixture.liveA, AGFixture.liveB, AGFixture.notitle, AGFixture.noinput])  // killed 제외 + 최근순

        let a = refs[0]
        XCTAssertEqual(a.tool, .agy)
        XCTAssertEqual(a.cwd, "/Users/test/proj")           // file:// → 로컬 경로
        XCTAssertEqual(a.title, "Fix tests")
        XCTAssertEqual(a.messageCount, 3)
        XCTAssertEqual(a.path, f.root + "/conversations/\(AGFixture.liveA).db")
        // 리더는 last_modified_time 을 lastActive 로 쓴다.
        XCTAssertEqual(a.lastActive,
                       SessionKit.SessionMeta.antigravityDate("2026-09-01 12:00:00.000000+00:00"))
    }

    func testDiscoverFallsBackToPreviewTitleAndModifiedTime() throws {
        let f = try fixture()
        let refs = f.reader.discover()
        XCTAssertEqual(refs[2].title, "미리보기 프롬프트")            // 제목이 비면 preview 대체
        XCTAssertEqual(refs[3].lastActive, SessionKit.SessionMeta.antigravityDate("2026-08-20 10:00:00.000000+00:00"))  // 입력 시각 없음 → 수정 시각
    }

    // MARK: - find / findPrefix

    func testFindExactMatch() throws {
        let f = try fixture()
        XCTAssertEqual(f.reader.find(id: AGFixture.liveA)?.id, AGFixture.liveA)
        XCTAssertNil(f.reader.find(id: "abcd"))               // 8자 미만 거부
    }

    func testFindPrefixAmbiguityRespectsLimitAndExcludesKilled() throws {
        let f = try fixture()
        XCTAssertEqual(f.reader.findPrefix(id: "aaaa1111", limit: 10).map({ $0.id }), [AGFixture.liveA, AGFixture.liveB])
        XCTAssertEqual(f.reader.findPrefix(id: "aaaa1111", limit: 1).map({ $0.id }), [AGFixture.liveA])  // limit 준수
        XCTAssertEqual(f.reader.findPrefix(id: AGFixture.liveB, limit: 10).map({ $0.id }), [AGFixture.liveB])    // 정확 일치는 단독
        XCTAssertTrue(f.reader.findPrefix(id: "dddd4444", limit: 10).isEmpty)               // killed 배제
        XCTAssertTrue(f.reader.findPrefix(id: "zzzz9999", limit: 10).isEmpty)
    }

    // MARK: - steps

    func testStepsExtractKoreanAndToolJSON() throws {
        let f = try fixture()
        let steps = f.reader.steps(f.refA)
        XCTAssertEqual(steps.map(\.type), [14, 15, 132, 101, 999])
        XCTAssertEqual(steps[0].payloadStrings.filter { $0.contains("안녕하세요") }.count, 2)  // 2중 저장 그대로 노출
        XCTAssertEqual(steps[2].metadataStrings.filter { $0.hasPrefix("{") }.count, 1)
        XCTAssertTrue(steps[2].metadataStrings.contains("EditFile"))
    }

    func testStepsOnMissingTranscriptReturnsEmpty() throws {
        let f = try fixture()
        let ref = SessionRef(tool: .agy, id: AGFixture.liveB, cwd: "", title: nil, lastActive: .now,
                             path: f.root + "/conversations/\(AGFixture.liveB).db", messageCount: 0)  // 전사본 파일 없음
        XCTAssertTrue(f.reader.steps(ref).isEmpty)
    }

    // MARK: - digest

    func testDigestDedupesUserTextAndAbsorbsToolCall() throws {
        let f = try fixture()
        let d = f.reader.digest(f.refA)
        XCTAssertEqual(d.userMessages, ["안녕하세요 세션 테스트입니다"])  // 2중 저장 + normalized 중복 제거
        XCTAssertEqual(d.agentMessages, ["작업을 완료했습니다. 빌드와 테스트를 모두 통과했습니다."])
        XCTAssertEqual(d.files, ["/tmp/FixtureProject/Sources/App.swift": 1])
        XCTAssertEqual(d.commands, ["swift test"])
        XCTAssertEqual(d.commandOutputs.map({ $0.command }), ["EditFile"])
        XCTAssertEqual(d.commandOutputs.map({ $0.stdoutLine }), ["Ran 2 tests"])
        XCTAssertEqual(d.turns.map({ $0.speaker }), [.user, .agent])
    }

    func testDigestUnknownStepCountedAndKnownIgnoredNotRecorded() throws {
        let f = try fixture()
        let d = f.reader.digest(f.refA)
        XCTAssertEqual(d.unknownEvents, ["step_999": 1])  // 드리프트 감지 입력
        XCTAssertFalse(d.unknownEvents.keys.contains { ["step_101", "step_17", "step_23"].contains($0) })
    }

    // MARK: - 문자열 run 추출

    func testStringsExtractsASCIIRunsSplitOnBinaryBytes() {
        XCTAssertEqual(AntigravitySessionReader.strings(in: Data("hello\u{00}world!".utf8)), ["hello", "world!"])
        let invalidBytes = Data("abcdef".utf8) + Data([0xFF, 0xFE]) + Data("ghij".utf8)  // 0xFF·0xFE 는 유효 UTF-8 이 아니다
        XCTAssertEqual(AntigravitySessionReader.strings(in: invalidBytes), ["abcdef", "ghij"])
        XCTAssertEqual(AntigravitySessionReader.strings(in: Data("ab\u{01}cdef".utf8)), ["cdef"])  // minRunLength 4 미만 폐기
        XCTAssertTrue(AntigravitySessionReader.strings(in: Data(), minRunLength: 4).isEmpty)
    }

    func testStringsKeepsMultibyteUTF8() {
        let korean = "한글 원문 보존"
        XCTAssertEqual(AntigravitySessionReader.strings(in: Data(korean.utf8)), [korean])
        let mixed = "결과: " + "ok"
        XCTAssertEqual(AntigravitySessionReader.strings(in: Data(mixed.utf8)), [mixed])
    }

    // MARK: - isHumanText / normalized

    func testIsHumanTextAcceptsProseAndRejectsIdentifiers() {
        XCTAssertTrue(AntigravitySessionReader.isHumanText("안녕하세요 세션 테스트입니다"))
        XCTAssertTrue(AntigravitySessionReader.isHumanText("작업을 완료했습니다. 테스트도 통과했습니다."))
        XCTAssertFalse(AntigravitySessionReader.isHumanText("/Users/test/proj/Sources/App.swift"))   // 절대 경로
        XCTAssertFalse(AntigravitySessionReader.isHumanText("79ff0223-aabb-4ccc-8ddd-001122334455")) // UUID
        XCTAssertFalse(AntigravitySessionReader.isHumanText("b$79ff0223aabbccdd001122334455ff"))    // hex 비율 과다
        XCTAssertFalse(AntigravitySessionReader.isHumanText("call_abc123"))                          // call id
        XCTAssertFalse(AntigravitySessionReader.isHumanText(#"{"AbsolutePath":"/tmp/a.swift"}""#))   // JSON 통째 run(꼬리 인용부까지 실측 형태)
        XCTAssertFalse(AntigravitySessionReader.isHumanText("ab"))                                   // 너무 짧음
    }

    func testNormalizedStripsQuoteAndWhitespaceDecorations() {
        XCTAssertEqual(AntigravitySessionReader.normalized("\n  안녕하세요 \n"), "안녕하세요")
        XCTAssertEqual(AntigravitySessionReader.normalized("\"안녕하세요\""), "안녕하세요")
        XCTAssertEqual(AntigravitySessionReader.normalized("'안녕하세요'"), "안녕하세요")
        XCTAssertEqual(AntigravitySessionReader.normalized("안녕하세요"), "안녕하세요")  // 꼬리 인용부 변형도 같은 값
    }
}
