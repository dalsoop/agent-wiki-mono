import XCTest
@testable import GujoStoreOpsCore

final class OpsPreferencesTests: XCTestCase {
    func testDefaultBaseIsProdWhenUnset() {
        XCTAssertEqual(OpsPreferences.endpointKey, StoreOpsStaffEndpoints.prodHostKey)
        XCTAssertFalse(OpsPreferences.baseURL.absoluteString.isEmpty)
    }

    /// `absoluteString.isEmpty` 만 보던 옛 단언은 `file:///` 를 통과시킨다 — 실물이 완전히
    /// 망가진 상태에서도 초록이었다. base 는 **네트워크 주소**여야 한다는 걸 직접 잰다.
    func testBaseURLIsNetworkAddressNotFilesystemRoot() {
        let url = OpsPreferences.baseURL
        XCTAssertNotEqual(url.scheme, "file", "Ops base 가 file:/// 로 퇴화했다: \(url)")
        XCTAssertTrue(["http", "https"].contains(url.scheme ?? ""), "scheme=\(url.scheme ?? "nil")")
        XCTAssertNotNil(url.host, "host 없는 base 로는 스태프 API 를 부를 수 없다: \(url)")
    }

    /// prod 키(`software-prod`)는 EndpointRouterKit 원장에 선언돼 있지 않다. 폴백 사슬이
    /// 끊기면 스킬 발행·폐기·다운로드 감사가 전부 파일 URL 을 때린다.
    func testStaffEndpointsResolveProdThroughFallbackChain() {
        let resolved = StoreOpsStaffEndpoints.resolvedHost(StoreOpsStaffEndpoints.prodHostKey)
        XCTAssertFalse(resolved.isEmpty, "prod 호스트가 어느 키로도 풀리지 않는다")
        XCTAssertTrue(resolved.hasPrefix("http"), "resolved=\(resolved)")

        for path in [
            StoreOpsStaffEndpoints.skillPublishPath,
            StoreOpsStaffEndpoints.skillDeprecatePath,
            StoreOpsStaffEndpoints.downloadPipelinePath,
        ] {
            let url = StoreOpsStaffEndpoints.url(path: path)
            XCTAssertNotEqual(url.scheme, "file", "\(path) 가 file URL 로 조립됐다: \(url)")
            XCTAssertTrue(url.absoluteString.hasSuffix(path), "\(url) 가 \(path) 로 끝나지 않는다")
        }
    }

    /// 폴백 사슬은 prod 키에만 적용한다 — 모르는 키가 슬그머니 prod 주소를 받으면
    /// 로컬로 보내려던 요청이 실서버로 간다.
    func testUnknownKeyDoesNotInheritProdFallback() {
        XCTAssertEqual(StoreOpsStaffEndpoints.resolvedHost("no-such-endpoint-key"), "")
    }

    func testHumanizeHostname() {
        let err = StoreOpsError.network("A server with the specified hostname could not be found.")
        let msg = OpsPreferences.humanize(err)
        XCTAssertTrue(
            msg.contains("서버에 연결")
                || msg.contains("Cannot reach")
                || msg.contains("OpsPreferences.return")
        )
    }

    func testHumanize401() {
        let err = StoreOpsError.http(401)
        // http error description is "HTTP 401"
        let msg = OpsPreferences.humanize(err)
        XCTAssertTrue(
            msg.contains("401")
                || msg.contains("인증")
                || msg.contains("Auth failed")
                || msg.contains("OpsPreferences.return-2")
        )
    }
}
