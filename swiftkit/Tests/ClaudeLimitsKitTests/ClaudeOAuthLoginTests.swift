import XCTest
@testable import ClaudeLimitsKit

final class ClaudeOAuthLoginTests: XCTestCase {
    func testBeginProducesPKCEAuthorizeURL() {
        let p = ClaudeOAuthLogin.begin()
        let s = p.authorizeURL.absoluteString
        XCTAssertTrue(s.hasPrefix("https://claude.com/cai/oauth/authorize?"))
        XCTAssertTrue(s.contains("code_challenge="))
        XCTAssertTrue(s.contains("code_challenge_method=S256"))
        XCTAssertTrue(s.contains("client_id="))
        XCTAssertFalse(p.verifier.isEmpty)
        XCTAssertFalse(p.state.isEmpty)
        // 매 호출 새 verifier/state.
        XCTAssertNotEqual(p.verifier, ClaudeOAuthLogin.begin().verifier)
    }

    func testBuildResultAssemblesBlobFromTokenResponse() {
        let resp: [String: Any] = [
            "access_token": "acc-xyz",
            "refresh_token": "ref-xyz",
            "expires_in": 3600.0,
            "scope": "user:inference user:profile",
            "subscription_type": "max",
            "organization": ["uuid": "org-123"],
            "account": ["email_address": "user@example.com"],
        ]
        let result = ClaudeOAuthLogin.buildResult(from: resp, accessToken: "acc-xyz")
        XCTAssertEqual(result.organizationUuid, "org-123")
        XCTAssertEqual(result.email, "user@example.com")

        let obj = try! JSONSerialization.jsonObject(with: result.blob) as! [String: Any]
        XCTAssertEqual(obj["organizationUuid"] as? String, "org-123")
        let oauth = obj["claudeAiOauth"] as! [String: Any]
        XCTAssertEqual(oauth["accessToken"] as? String, "acc-xyz")
        XCTAssertEqual(oauth["refreshToken"] as? String, "ref-xyz")
        XCTAssertEqual(oauth["subscriptionType"] as? String, "max")
        XCTAssertNotNil(oauth["expiresAt"])   // ms epoch 로 저장
        XCTAssertEqual((oauth["scopes"] as? [String])?.count, 2)
    }

    func testCompleteRejectsStateMismatch() async {
        do {
            _ = try await ClaudeOAuthLogin.complete(pasted: "somecode#WRONG", verifier: "v", state: "RIGHT")
            XCTFail("state 불일치인데 통과함")
        } catch let e as ClaudeOAuthLoginError {
            XCTAssertEqual(e, .stateMismatch)
        } catch {
            XCTFail("예상과 다른 오류: \(error)")
        }
    }
}
