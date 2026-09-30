import Foundation
import GujoAuthKit
import HTTPClientKit
import Testing
import os

@testable import GujoStaffAPIKit

/// 요청을 기록하고 경로별 고정 응답을 돌려주는 스텁 전송.
final class StubHTTP: HTTPClient, Sendable {
    struct Call: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data?

        func jsonObject() -> [String: Any] {
            guard let body else { return [:] }
            do {
                return try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
            } catch {
                return [:]
            }
        }
    }

    private struct Memory: Sendable {
        var calls: [Call] = []
    }

    private let responses: [String: (Int, String)]
    private let memory = OSAllocatedUnfairLock(initialState: Memory())

    init(_ responses: [String: (Int, String)]) { self.responses = responses }

    func send(
        method: String, url: URL, headers: [String: String], body: Data?
    ) async throws -> (status: Int, data: Data) {
        memory.withLock { state in
            state.calls.append(Call(method: method, url: url, headers: headers, body: body))
        }
        let hit = responses["\(method) \(url.path)"] ?? responses[url.path]
        guard let hit else {
            return (404, Data(#"{"error":"unscripted"}"#.utf8))
        }
        return (hit.0, Data(hit.1.utf8))
    }

    var last: Call? { memory.withLock { $0.calls.last } }
    var calls: [Call] { memory.withLock { $0.calls } }
}

let baseURL = URL(string: "https://gujo.example") ?? URL(fileURLWithPath: "/gujo.example")

/// 주어진 abilities 로 로그인된 클라이언트.
func makeClient(_ http: StubHTTP, abilities: [StaffAbility]) -> GujoStaffAPIClient {
    let auth = GujoStaffAuth(
        http: http, store: InMemorySessionStore(), fallback: NoStaffTokenFallback(), machine: NoMachineStaffToken(),
        baseURL: baseURL, sleep: { _ in }, now: { Date(timeIntervalSince1970: 1_780_000_000) })
    auth.adopt(StaffSession(
        token: "gst_test", expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
        abilities: abilities, staff: StaffIdentity(id: 1, name: "T", email: "t@gujo.example")))
    return GujoStaffAPIClient(auth: auth, http: http, baseURL: baseURL)
}

@Suite("GujoStaffAPIKit — 계약 §5 타입 클라이언트")
struct GujoStaffAPIClientTests {

    @Test("customers.index — Bearer 토큰·페이지 쿼리·Laravel 페이지 봉투")
    func customersIndex() async throws {
        let http = StubHTTP([
            "/api/commerce/staff/customers": (200, """
                {"data":[{"id":1,"name":"A","email":"a@x","created_at":"2026-01-02T03:04:05Z"},
                         {"id":2,"name":"B","email":null}],
                 "meta":{"current_page":2,"last_page":9,"total":170}}
                """),
        ])
        let page = try await makeClient(http, abilities: [.customersRead]).commerce.customers.index(search: "a", page: 2)

        #expect(page.data.map(\.id) == [1, 2])
        #expect(page.data.first?.createdAt == Date(timeIntervalSince1970: 1_767_323_045))
        #expect(page.currentPage == 2)
        #expect(page.total == 170)
        let call = try #require(http.last)
        #expect(call.method == "GET")
        #expect(call.headers["Authorization"] == "Bearer gst_test")
        #expect(call.url.query == "page=2&q=a")
    }

    @Test("orders.refund — POST 본문과 단건 봉투 해제")
    func ordersRefund() async throws {
        let http = StubHTTP([
            "/api/commerce/staff/orders/77/refund": (200, #"{"data":{"id":77,"status":"refunded","total":12000}}"#),
        ])
        let order = try await makeClient(http, abilities: [.ordersRefund]).commerce.orders.refund(
            77, RefundRequest(amount: 12000, reason: "duplicate"))

        #expect(order.status == "refunded")
        let call = try #require(http.last)
        #expect(call.method == "POST")
        #expect((call.jsonObject()["amount"] as? NSNumber)?.doubleValue == 12000)
        #expect(call.jsonObject()["reason"] as? String == "duplicate")
    }

    @Test("inquiries.close — 맨몸 리소스 응답도 받는다")
    func inquiriesClose() async throws {
        let http = StubHTTP([
            "/api/support/staff/inquiries/5/close": (
                200, #"{"id":5,"subject":"s","status":"closed","user_id":3,"user_email":"b@example.com","messages":[]}"#
            ),
        ])
        let inquiry = try await makeClient(http, abilities: [.inquiriesWrite]).support.inquiries.close(5)
        #expect(inquiry.status == "closed")
        #expect(http.last?.method == "POST")
    }

    @Test("inquiries — 게스트 문의·신고 메타·첨부 링크(계약 §5)")
    func inquiriesContract() async throws {
        let http = StubHTTP([
            "GET /api/support/staff/inquiries": (
                200,
                #"{"data":[{"id":7,"subject":"영수증","category":"billing","kind":"general","status":"open","#
                    + #""user_id":null,"user_email":"v@example.com","is_guest":true,"#
                    + #""created_at":"2026-09-30T01:00:00+00:00","updated_at":"2026-09-30T01:00:00+00:00","message_count":1,"#
                    + #""latest_body_preview":"영수증","latest_is_staff":false}],"meta":{"count":1,"limit":20}}"#
            ),
            "GET /api/support/staff/inquiries/9": (
                200,
                #"{"data":{"id":9,"subject":"앱이 닫힙니다","category":"bug","kind":"app_report","status":"open","#
                    + #""user_id":3,"user_email":"b@example.com","guest_name":null,"is_guest":false,"#
                    + #""report":{"app_bundle_id":"ai.gujo.demo","app_version":"1.4.2","macos_version":"15.6","#
                    + #""device_id":"d-1","fingerprint":"abc"},"created_at":"2026-09-30T01:00:00+00:00","#
                    + #""updated_at":"2026-09-30T01:00:00+00:00","messages":[{"id":1,"is_staff":false,"body":"본문","#
                    + #""created_at":"2026-09-30T01:00:00+00:00","attachments":[{"id":5,"kind":"diagnostic_bundle","#
                    + #""original_name":"diag.zip","size":14,"mime_type":"application/zip","#
                    + #""download_url":"/api/support/staff/inquiries/9/attachments/5"}]}]}}"#
            ),
            "GET /api/support/staff/inquiries/9/attachments/5": (
                200,
                #"{"data":{"id":5,"original_name":"diag.zip","size":14,"mime_type":"application/zip","#
                    + #""url":"https://bucket.example.invalid/x?sig=1","expires_at":"2026-09-30T01:05:00Z"}}"#
            ),
        ])
        let client = makeClient(http, abilities: [.inquiriesRead])

        let page = try await client.support.inquiries.index(status: "open", limit: 20)
        #expect(page.data.first?.userId == nil)
        #expect(page.data.first?.isGuest == true)
        #expect(http.last?.url.query?.contains("limit=20") == true)

        let detail = try await client.support.inquiries.show(9)
        #expect(detail.report?.appBundleId == "ai.gujo.demo")
        #expect(detail.messages.first?.attachments?.first?.downloadUrl == "/api/support/staff/inquiries/9/attachments/5")

        let link = try await client.support.inquiries.attachmentLink(9, attachment: 5)
        #expect(link.url.absoluteString == "https://bucket.example.invalid/x?sig=1")
    }

    @Test("ops.packages — list 는 배열 맨몸 응답, publish 는 POST /ops/v1/packages")
    func opsPackages() async throws {
        let http = StubHTTP([
            "GET /ops/v1/packages": (200, #"[{"slug":"agent-deck","version":"1.2.3","channel":"stable"}]"#),
            "POST /ops/v1/packages": (200, #"{"slug":"agent-deck","version":"1.2.4","channel":"stable"}"#),
        ])
        let client = makeClient(http, abilities: [.opsPackages])
        let list = try await client.ops.packages.list()
        #expect(list.data.map(\.slug) == ["agent-deck"])
        #expect(list.total == nil)

        let published = try await client.ops.packages.publish(
            OpsPackagePublish(slug: "agent-deck", version: "1.2.4"))
        #expect(published.version == "1.2.4")
        let call = try #require(http.last)
        #expect(call.method == "POST")
        #expect(call.url.path == "/ops/v1/packages")
        #expect(call.jsonObject()["version"] as? String == "1.2.4")
    }

    @Test("storeReleasesIntake — /store/releases/intake 에 ReleaseIntake 로")
    func storeReleasesIntake() async throws {
        let http = StubHTTP([
            "/store/releases/intake": (201, #"{"id":9,"slug":"s","version":"1.0.0","status":"queued"}"#),
        ])
        let receipt = try await makeClient(http, abilities: [.releaseIntake]).intake.storeReleasesIntake(
            ReleaseIntake(slug: "s", version: "1.0.0", sha256: "abc"))
        #expect(receipt.status == "queued")
        let call = try #require(http.last)
        #expect(call.jsonObject()["sha256"] as? String == "abc")
        #expect(call.headers["Content-Type"] == "application/json")
    }

    @Test("skills.publish — manifest JSON 을 그대로 실어 보낸다")
    func skillsPublish() async throws {
        let http = StubHTTP([
            "/api/skills/publish": (200, #"{"slug":"my-skill","version":"2.0.0","status":"published"}"#),
        ])
        let record = try await makeClient(http, abilities: [.skillPublish]).skills.publish(
            SkillPublish(slug: "my-skill", version: "2.0.0", manifest: .object(["name": .string("My Skill")])))
        #expect(record.status == "published")
        let manifest = http.last?.jsonObject()["manifest"] as? [String: Any]
        #expect(manifest?["name"] as? String == "My Skill")
    }

    @Test("ability 가 세션에 없으면 서버를 치지 않고 이름을 실어 던진다")
    func localAbilityCheck() async throws {
        let http = StubHTTP([:])
        let client = makeClient(http, abilities: [.customersRead])
        await #expect(throws: GujoAuthError.missingAbility(.ordersRefund)) {
            try await client.commerce.orders.refund(1)
        }
        #expect(http.calls.isEmpty)
    }

    @Test("서버 403 은 forbidden 에 서버가 밝힌 ability 이름을 싣는다")
    func serverForbidden() async throws {
        let http = StubHTTP([
            "/api/commerce/staff/customers/3": (403, #"{"error":"forbidden","required_ability":"CustomersRead"}"#),
        ])
        let client = makeClient(http, abilities: [.customersRead])
        let expected = GujoStaffAPIError.forbidden(
            required: .customersRead, serverAbility: "CustomersRead", path: "/api/commerce/staff/customers/3")
        await #expect(throws: expected) {
            try await client.commerce.customers.show(3)
        }
        #expect(expected.missingAbilityName == "CustomersRead")
        #expect(expected.localizedDescription.contains("CustomersRead"))
    }

    @Test("서버 403 에 이름이 없으면 클라이언트 매핑 이름으로 채운다")
    func serverForbiddenWithoutName() async throws {
        let http = StubHTTP(["/ops/v1/health": (403, #"{"error":"forbidden"}"#)])
        do {
            _ = try await makeClient(http, abilities: [.opsHealth]).ops.health()
            Issue.record("403 이 던져져야 한다")
        } catch let error as GujoStaffAPIError {
            #expect(error.missingAbilityName == "OpsHealth")
        }
    }

    @Test("401 · 404 · 422 · 5xx 매핑, 204 는 Empty")
    func statusMapping() async throws {
        let http = StubHTTP([
            "/api/commerce/staff/customers/1/devices/2/revoke": (204, ""),
            "/api/support/staff/inquiries/404": (404, ""),
            "/api/support/staff/inquiries/422/reopen": (422, #"{"message":"already open"}"#),
            "/ops/v1/devices/500": (500, #"{"error":"boom"}"#),
            "/api/skills/x": (401, ""),
        ])
        let client = makeClient(
            http, abilities: [.devicesRevoke, .inquiriesRead, .inquiriesWrite, .opsDevices, .skillPublish])

        try await client.commerce.customers.devicesRevoke(1, deviceId: 2)
        await #expect(throws: GujoStaffAPIError.notFound(path: "/api/support/staff/inquiries/404")) {
            try await client.support.inquiries.show(404)
        }
        await #expect(throws: GujoStaffAPIError.validation(
            status: 422, message: "already open", path: "/api/support/staff/inquiries/422/reopen")
        ) {
            try await client.support.inquiries.reopen(422)
        }
        await #expect(throws: GujoStaffAPIError.server(status: 500, message: "boom", path: "/ops/v1/devices/500")) {
            try await client.ops.devices.show(500)
        }
        await #expect(throws: GujoStaffAPIError.unauthorized(path: "/api/skills/x")) {
            try await client.skills.delete(slug: "x")
        }
    }

    @Test("로그인 안 됐으면 어떤 호출도 notLoggedIn")
    func notLoggedIn() async throws {
        let http = StubHTTP([:])
        let auth = GujoStaffAuth(
            http: http, store: InMemorySessionStore(), fallback: NoStaffTokenFallback(), machine: NoMachineStaffToken(), baseURL: baseURL)
        let client = GujoStaffAPIClient(auth: auth, http: http, baseURL: baseURL)
        await #expect(throws: GujoAuthError.notLoggedIn) { _ = try await client.commerce.products() }
        #expect(http.calls.isEmpty)
    }
}
