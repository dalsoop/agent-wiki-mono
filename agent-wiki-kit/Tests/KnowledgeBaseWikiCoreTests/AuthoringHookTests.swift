import XCTest
@testable import KnowledgeBaseWikiCore

/// 훅은 원장 저작 조건을 남기는 유일한 통로다 — 그리고 **절대 세션을 막으면 안 된다.**
///
/// 주의: 여기서 `AuthoringHook.run()` 을 경로 없이 부르지 마라. 기본 경로는
/// `homeDirectoryForCurrentUser` 라 `HOME` 을 무시하고 실제 홈 파일을 덮는다.
final class AuthoringHookTests: XCTestCase {
    private var directory: URL!
    private var target: URL { directory.appendingPathComponent("authoring.json") }

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("authoring-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 하네스가 주는 키 이름이 제각각이라 후보를 순서대로 본다.
    func testExtractsModelAndSessionFromEvent() {
        let json = #"{"session_id":"abc","model":"claude-opus-5","source":"claude-code"}"#
        let authoring = AuthoringHook.authoring(fromEventJSON: Data(json.utf8), hostName: "mac")
        XCTAssertEqual(authoring.model, "claude-opus-5")
        XCTAssertEqual(authoring.session, "abc")
        XCTAssertEqual(authoring.runtime, "claude-code")
        XCTAssertEqual(authoring.host, "mac")
    }

    /// camelCase 로 오는 하네스도 있다.
    func testAcceptsCamelCaseKeys() {
        let json = #"{"sessionId":"s1","modelId":"m1"}"#
        let authoring = AuthoringHook.authoring(fromEventJSON: Data(json.utf8), hostName: "mac")
        XCTAssertEqual(authoring.session, "s1")
        XCTAssertEqual(authoring.model, "m1")
        // source 가 없으면 claude-code 로 본다 — 이 훅을 다는 하네스가 그거다.
        XCTAssertEqual(authoring.runtime, "claude-code")
    }

    /// **아는 것만 적는다.** 빈 문자열을 값으로 취급하면 "모른다" 와 구분이 사라진다.
    func testBlankValuesAreNotRecorded() {
        let json = #"{"session_id":"   ","model":""}"#
        let authoring = AuthoringHook.authoring(fromEventJSON: Data(json.utf8), hostName: "mac")
        XCTAssertNil(authoring.session)
        XCTAssertNil(authoring.model)
    }

    /// 깨진 payload 도 던지지 않는다 — 훅이 실패하면 하네스 세션이 멈춘다.
    func testGarbagePayloadDoesNotThrow() {
        let authoring = AuthoringHook.authoring(fromEventJSON: Data("not json".utf8),
                                                hostName: "mac")
        XCTAssertEqual(authoring.runtime, "claude-code")
        XCTAssertNil(authoring.session)
    }

    /// 쓴 값을 읽는 쪽이 그대로 복원해야 한다 — 왕복이 깨지면 저작 조건이 유실된다.
    func testWriteThenAmbientRoundTrip() throws {
        let authoring = Authoring(runtime: "claude-code", model: "claude-opus-5",
                                  session: "s-9", host: "mac")
        XCTAssertTrue(AuthoringHook.write(authoring, to: target))

        let restored = Authoring.ambient(environment: [:], fileURL: target)
        XCTAssertEqual(restored.model, "claude-opus-5")
        XCTAssertEqual(restored.session, "s-9")
    }

    /// 환경변수가 파일을 이긴다(기존 규약) — 훅이 그걸 뒤집으면 배치 작업이 거짓을 남긴다.
    func testEnvironmentStillWinsOverHookFile() throws {
        XCTAssertTrue(AuthoringHook.write(
            Authoring(runtime: "claude-code", model: "from-file", session: "file-session"),
            to: target))

        let resolved = Authoring.ambient(environment: ["AGENT_WIKI_MODEL": "from-env"],
                                         fileURL: target)
        XCTAssertEqual(resolved.model, "from-env")
        XCTAssertEqual(resolved.session, "file-session")
    }

    /// 빈 stdin 이면 아무것도 안 쓴다 — 멀쩡한 파일을 빈 값으로 덮으면 안 된다.
    func testEmptyInputLeavesFileUntouched() throws {
        try Data(#"{"model":"keep-me"}"#.utf8).write(to: target)
        AuthoringHook.run(input: FileHandle(forReadingAtPath: "/dev/null")!, url: target)
        XCTAssertEqual(Authoring.ambient(environment: [:], fileURL: target).model, "keep-me")
    }
}
