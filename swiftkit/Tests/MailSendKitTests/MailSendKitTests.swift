import XCTest
@testable import MailSendKit

final class MailSendKitTests: XCTestCase {
    func testRetryPolicyExponential() {
        let policy = RetryPolicy.standard
        XCTAssertEqual(policy.delayAfter(attempt: 1), 1)
        XCTAssertEqual(policy.delayAfter(attempt: 2), 2)
        XCTAssertNil(policy.delayAfter(attempt: 3))
    }

    func testRecordingAdapterDefaultSuccess() async throws {
        let adapter = RecordingMailSendAdapter(name: "mock")
        let receipt = try await adapter.send(
            MailSendRequest(
                to: "a@b.c",
                fromEmail: "f@b.c",
                fromName: "F",
                subject: "s",
                html: "<p>h</p>",
                text: "h",
                tracking: .init(templateId: "t", data: [:], messageId: "m1")
            )
        )
        XCTAssertEqual(receipt.provider, "mock")
        XCTAssertEqual(adapter.requests.count, 1)
        XCTAssertEqual(adapter.requests[0].headers, [:])
        XCTAssertNil(adapter.requests[0].replyTo)
    }

    func testNewsletterStyleHeadersAndReplyTo() {
        let request = MailSendRequest(
            to: "a@b.c",
            fromEmail: "f@b.c",
            fromName: "F",
            replyTo: "r@b.c",
            subject: "s",
            html: "<p>h</p>",
            text: "h",
            tracking: .init(
                templateId: "t",
                messageId: "m1",
                headers: ["List-Unsubscribe": "<https://u>"]
            )
        )
        XCTAssertEqual(request.replyTo, "r@b.c")
        XCTAssertEqual(request.headers["List-Unsubscribe"], "<https://u>")
        XCTAssertEqual(request.data, [:])
        XCTAssertEqual(request.campaignId, "")
    }

    func testRequestAcceptsFlatTemplateFields() {
        let request = MailSendRequest(
            to: "a@b.c",
            fromEmail: "f@b.c",
            fromName: "F",
            subject: "s",
            html: "<p>h</p>",
            text: "h",
            templateId: "t",
            data: ["k": "v"],
            messageId: "m1"
        )
        XCTAssertEqual(request.templateId, "t")
        XCTAssertEqual(request.data["k"], "v")
        XCTAssertEqual(request.messageId, "m1")
    }

    func testMustacheEscapesHTMLButNotTriple() {
        let out = MustacheRenderer.render(
            "<p>{{name}}</p><pre>{{{raw}}}</pre>",
            data: ["name": "A & B", "raw": "<b>x</b>"],
            htmlEscape: true
        )
        XCTAssertEqual(out, "<p>A &amp; B</p><pre><b>x</b></pre>")
    }

    func testMustacheFlattenNestedJSON() throws {
        let flat = try MustacheRenderer.flattenJSON(#"{"user":{"name":"한"},"n":3,"ok":true}"#)
        XCTAssertEqual(flat["user.name"], "한")
        XCTAssertEqual(flat["n"], "3")
        XCTAssertEqual(flat["ok"], "1")
    }

    func testMustacheInvalidJSON() {
        XCTAssertThrowsError(try MustacheRenderer.flattenJSON("{")) { error in
            guard case MustacheError.invalidJSON = error else {
                return XCTFail("expected invalidJSON, got \(error)")
            }
        }
    }

    func testRenderedMailDualEscape() {
        let rendered = MustacheRenderer.render(
            subject: "Hi {{userName}}",
            html: "<p>{{userName}}</p>",
            text: "Hi {{userName}}",
            data: ["userName": "A <B>"]
        )
        XCTAssertEqual(rendered.subject, "Hi A <B>")
        XCTAssertEqual(rendered.text, "Hi A <B>")
        XCTAssertEqual(rendered.html, "<p>A &lt;B&gt;</p>")
    }

    func testRateLimiterSleepsRemainder() async throws {
        struct Paths: RateLimitPathing {
            let root: URL
            var rateLimitFile: URL { root.appendingPathComponent("rate-limit.json") }
            func ensureLayout() throws {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            }
        }
        let clock = ControllableMailClock(now: Date(timeIntervalSince1970: 50))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mailsend-rate-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let limiter = RateLimiter(paths: Paths(root: root), clock: clock)
        try await limiter.waitTurn()
        clock.advance(by: 0.25)
        try await limiter.waitTurn()
        XCTAssertEqual(clock.sleeps.last ?? -1, 0.75, accuracy: 0.001)
    }
}
