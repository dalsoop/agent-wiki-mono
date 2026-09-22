import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// 저작 provenance 계약 — 이 객체를 무엇이 어떤 조건에서 썼나.
///
/// 원장은 지금까지 `author` 문자열 하나만 남겼다. 같은 `agent:claude@macbook` 이 어떤
/// 모델로 무엇을 얼마나 읽고 썼는지 구분되지 않아, 나중에 "이 판단을 믿어도 되나"를
/// 잴 근거가 없었다. 원장의 절반이 자동 배치 산출물이라 특히 그렇다.
@Suite struct AuthoringProvenanceTests {
    private func makeStore() -> LedgerStore {
        LedgerStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-authoring-\(UUID())", isDirectory: true))
    }

    /// 저작 기록은 **정체성 밖**이다 — 같은 지식을 더 비싸게 썼다고 다른 객체가 되면 안 된다.
    @Test func authoringDoesNotChangeContentIdentity() {
        let now = Date()
        let bare = LedgerObject(
            id: "", published: now, author: "test", title: "근거: 같은 지식",
            type: "evidence", body: "본문")
        let costly = LedgerObject(id: "", published: now, author: "test", title: "근거: 같은 지식", type: "evidence", body: "본문", extras: LedgerObject.Extras(authoring: Authoring(model: "claude-opus-5", tokensIn: 90_000, tokensOut: 4_000)))
        #expect(bare.contentID() == costly.contentID())
    }

    /// 그래도 저장·복원은 된다(직렬화 왕복).
    @Test func authoringSurvivesRoundTrip() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let authoring = Authoring(
            runtime: "claude-code", model: "claude-opus-5", session: "abc-123",
            tokensIn: 48_210, tokensOut: 1_930, contextObjects: 37, host: "macbook")
        let published = try store.publish(author: "agent:claude@macbook", title: "근거: 왕복", type: "evidence", body: "본문", extras: LedgerPublishExtras(authoring: authoring))

        let reloaded = try #require(store.scan().first { $0.id == published.id })
        #expect(reloaded.authoring == authoring)
        #expect(reloaded.authoring?.tokensOut == 1_930)
        #expect(reloaded.authoring?.contextObjects == 37)
    }

    /// 무결성 검증은 저작 기록에 영향받지 않는다(코어 밖 필드).
    @Test func integrityUnaffectedByAuthoring() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.root) }
        _ = try store.publish(author: "test", title: "근거: 무결성", type: "evidence", body: "본문", extras: LedgerPublishExtras(authoring: Authoring(model: "m", tokensOut: 10)))
        #expect(store.verify().isEmpty)
    }

    /// 아는 것만 채운다 — 없는 값을 0 으로 만들어 "0 토큰으로 썼다"는 거짓을 만들지 않는다.
    @Test func absentValuesStayAbsent() {
        let partial = Authoring.fromEnvironment(["AGENT_WIKI_MODEL": "claude-opus-5"])
        #expect(partial.model == "claude-opus-5")
        #expect(partial.tokensIn == nil)
        #expect(partial.tokensOut == nil)
        #expect(partial.contextObjects == nil)

        let empty = Authoring()
        #expect(empty.isEmpty)
        #expect(empty.jsonLine == nil)
        #expect(empty.summary == "기록 없음")
    }

    /// 환경에서 읽은 값이 그대로 실린다.
    @Test func environmentPopulatesWhatHarnessProvides() {
        let authoring = Authoring.fromEnvironment([
            "AGENT_WIKI_RUNTIME": "claude-code",
            "AGENT_WIKI_MODEL": "claude-opus-5",
            "AGENT_WIKI_TOKENS_IN": "48210",
            "AGENT_WIKI_TOKENS_OUT": "1930",
            "AGENT_WIKI_CONTEXT_OBJECTS": "37",
            "AGENT_WIKI_HOST": "macbook",
        ])
        #expect(authoring.model == "claude-opus-5")
        #expect(authoring.tokensIn == 48_210)
        #expect(authoring.contextObjects == 37)
        #expect(authoring.summary.contains("48210→1930"))
        // JSON 왕복
        let decoded = Authoring(jsonLine: authoring.jsonLine)
        #expect(decoded == authoring)
    }
}

/// 배경 저작 기록 — 하네스가 남긴 세션 파일을 발행이 읽는다는 계약.
///
/// 환경변수만 보던 때는 실제로 **아무도 안 채웠다**(실측 2026-08-04: authoring 실린
/// 객체 0개). 모델·세션은 하네스만 알고 훅 stdin 으로만 오는데, 훅은 뒤이은 셸의
/// 환경을 바꿀 수 없기 때문이다. 그래서 훅이 파일에 적고 CLI 가 읽는다.
@Suite struct AuthoringAmbientTests {
    private func writeAmbient(_ json: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-ambient-\(UUID()).json")
        do { try Data(json.utf8).write(to: url) } catch { _ = error }
        return url
    }

    /// 환경이 비어도 세션 파일이 있으면 채워진다.
    @Test func sessionFileFillsWhenEnvironmentIsEmpty() {
        let file = writeAmbient(#"{"model":"claude-opus-5","session":"s-1","runtime":"claude-code"}"#)
        defer { try? FileManager.default.removeItem(at: file) }
        let authoring = Authoring.ambient(environment: [:], fileURL: file)
        #expect(authoring.model == "claude-opus-5")
        #expect(authoring.session == "s-1")
    }

    /// **환경변수가 세션 파일을 이긴다** — 배치 작업이 자기 조건을 정확히 남길 수 있게.
    @Test func environmentWinsOverSessionFile() {
        let file = writeAmbient(#"{"model":"from-file","session":"s-1"}"#)
        defer { try? FileManager.default.removeItem(at: file) }
        let authoring = Authoring.ambient(
            environment: ["AGENT_WIKI_MODEL": "from-env", "AGENT_WIKI_TOKENS_OUT": "42"],
            fileURL: file)
        #expect(authoring.model == "from-env")
        #expect(authoring.tokensOut == 42)
        #expect(authoring.session == "s-1")   // 환경에 없는 값은 파일에서 채운다
    }

    /// 파일이 없거나 깨져도 발행을 막지 않는다 — 기록은 부수 정보다.
    @Test func brokenOrMissingFileIsHarmless() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-absent-\(UUID()).json")
        let fromMissing = Authoring.ambient(environment: ["AGENT_WIKI_MODEL": "m"], fileURL: missing)
        #expect(fromMissing.model == "m")

        let broken = writeAmbient("이건 JSON 이 아니다")
        defer { try? FileManager.default.removeItem(at: broken) }
        let fromBroken = Authoring.ambient(environment: [:], fileURL: broken)
        #expect(fromBroken.model == nil)
    }
}
