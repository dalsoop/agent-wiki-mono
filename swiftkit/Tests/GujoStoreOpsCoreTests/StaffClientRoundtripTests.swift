import Foundation
import XCTest
@testable import GujoStoreOpsCore

final class StaffClientRoundtripTests: XCTestCase {
    private func baseURL() throws -> URL {
        try XCTUnwrap(URL(string: "https://apps.gujo.ai"))
    }



    func testPublishDeprecateAuditRoundtrip() async throws {
        let base = try baseURL()
        let provider = StaticStaffTokenProvider(token: "staff-test-token")
        let http = StubStaffHTTP { request in
            XCTAssertEqual(request.headers["Authorization"], "Bearer staff-test-token")
            let path = request.url.path
            if request.method == "POST", path.hasSuffix("/api/skills/publish") {
                XCTAssertNotNil(request.body)
                return try staffJSONResponse([
                    "ok": true,
                    "result": [
                        "name": "demo-skill",
                        "version": "1.2.0",
                        "message": "published",
                    ],
                ])
            }
            if request.method == "POST", path.hasSuffix("/api/skills/deprecate") {
                return try staffJSONResponse([
                    "ok": true,
                    "result": [
                        "name": "demo-skill",
                        "version": "1.2.0",
                        "message": "deprecated",
                    ],
                ])
            }
            if request.method == "GET", path.hasSuffix("/api/downloads/pipeline") {
                return try staffJSONResponse([
                    "ok": true,
                    "result": [
                        "contract_version": "1.1.0",
                        "ready": true,
                        "platforms": [
                            [
                                "platform": "macos",
                                "status": "ready",
                                "version": "1.0.0",
                                "download_path": "/download/Gujo.dmg",
                            ],
                        ],
                    ],
                ])
            }
            XCTFail("unexpected \(request.method) \(request.url)")
            return StaffHTTPResponse(status: 500, data: Data())
        }

        let skills = SkillStaffClient(baseURL: base, tokenProvider: provider, http: http)
        let published = try await skills.publish(
            SkillMutationRequest(name: "demo-skill", version: "1.2.0", body: "---\nname: demo-skill\n")
        )
        XCTAssertTrue(published.ok)
        XCTAssertEqual(published.action, "publish")
        XCTAssertEqual(published.name, "demo-skill")
        XCTAssertEqual(published.version, "1.2.0")

        let deprecated = try await skills.deprecate(
            SkillMutationRequest(name: "demo-skill", version: "1.2.0")
        )
        XCTAssertTrue(deprecated.ok)
        XCTAssertEqual(deprecated.action, "deprecate")
        XCTAssertEqual(deprecated.name, "demo-skill")

        let audit = try await DownloadPipelineStaffClient(
            baseURL: base,
            tokenProvider: provider,
            http: http
        ).audit()
        XCTAssertTrue(audit.ok)
        XCTAssertTrue(audit.ready)
        XCTAssertEqual(audit.contractVersion, "1.1.0")
        XCTAssertEqual(audit.platforms.first?.platform, "macos")
        XCTAssertEqual(audit.statusCode, 200)
    }

    func testMissingTokenFailsClosed() async throws {
        let http = StubStaffHTTP { _ in
            XCTFail("HTTP must not run without a staff token")
            return StaffHTTPResponse(status: 200, data: Data())
        }
        let skills = SkillStaffClient(
            baseURL: try baseURL(),
            tokenProvider: StaticStaffTokenProvider(token: nil),
            http: http
        )
        do {
            _ = try await skills.publish(SkillMutationRequest(name: "x"))
            XCTFail("expected missingToken")
        } catch StoreOpsStaffError.missingToken {
            // expected
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testStoreOpsClientWrappersRoundtrip() async throws {
        let provider = StaticStaffTokenProvider(token: "staff-test-token")
        let http = StubStaffHTTP { request in
            let path = request.url.path
            if request.method == "POST", path.hasSuffix("/api/skills/publish") {
                return try staffJSONResponse(["ok": true, "result": ["name": "w", "version": "1"]])
            }
            if request.method == "POST", path.hasSuffix("/api/skills/deprecate") {
                return try staffJSONResponse(["ok": true, "result": ["name": "w"]])
            }
            if request.method == "GET", path.hasSuffix("/api/downloads/pipeline") {
                return try staffJSONResponse([
                    "ok": true,
                    "result": ["ready": true, "platforms": [["platform": "macos", "status": "ready"]]],
                ])
            }
            return StaffHTTPResponse(status: 404, data: Data())
        }
        let client = StoreOpsClient(
            mode: .opsAPI,
            opsBaseURL: try baseURL(),
            tokenProvider: provider,
            staffHTTP: http
        )
        let published = try await client.publishSkill(SkillMutationRequest(name: "w", version: "1"))
        XCTAssertEqual(published.action, "publish")
        let deprecated = try await client.deprecateSkill(SkillMutationRequest(name: "w"))
        XCTAssertEqual(deprecated.action, "deprecate")
        let audit = try await client.auditDownloadPipeline()
        XCTAssertTrue(audit.ok)
    }
}

private func staffJSONResponse(_ object: [String: Any], status: Int = 200) throws -> StaffHTTPResponse {
    StaffHTTPResponse(status: status, data: try JSONSerialization.data(withJSONObject: object))
}
