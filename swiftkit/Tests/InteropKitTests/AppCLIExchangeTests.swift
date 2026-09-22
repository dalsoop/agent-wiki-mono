import XCTest
@testable import InteropKit

final class AppCLIExchangeTests: XCTestCase {
    func testTenantsReadRawArray() throws {
        let json = """
        [{"id":"tenant:personal","displayName":"본인","owner":"me","slug":"personal"}]
        """
        let rows = try AppCLIExchange.tenants(from: json)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, "tenant:personal")
        XCTAssertEqual(rows[0].slug, "personal")
    }

    func testTenantsReadEnvelopeArray() throws {
        let json = """
        {"ok":true,"result":[{"id":"tenant:wife","displayName":"배우자","owner":"p","slug":"wife"}]}
        """
        let rows = try AppCLIExchange.tenants(from: json)
        XCTAssertEqual(rows.map(\.slug), ["wife"])
    }

    func testTenantsReadWrappedKey() throws {
        let json = """
        {"ok":true,"result":{"tenants":[{"id":"a","displayName":"A","owner":"","slug":"a"}]}}
        """
        XCTAssertEqual(try AppCLIExchange.tenants(from: json).map(\.id), ["a"])
    }

    func testAccountBillingLegacyKeys() throws {
        let now = Date(timeIntervalSince1970: 1_777_200_000)
        let json = """
        {"ok":true,"result":{"rows":[{"id":"y1","client":"cursor","label":"me","plan":"Ultra","monthlyAmount":200,"currency":"USD","deal":"Ultra /yr","renewsAt":"2026-09-01T00:00:00Z","promoEndsInDays":10}]}}
        """
        let rows = try AppCLIExchange.accountBilling(from: json, now: now)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "Ultra (cursor)")
        XCTAssertEqual(rows[0].amount.majorAmount, 200)
        XCTAssertEqual(rows[0].period, .yearly)
        XCTAssertEqual(rows[0].nextBillingDate, "2026-09-01")
        XCTAssertEqual(rows[0].promoEndsOn, CLIExchangeDay.addingDays(10, to: now))
        XCTAssertEqual(rows[0].source?.key, "ai-cli-account-manager#y1")
    }

    func testMoneyLedgerMinorUnits() throws {
        let json = """
        {"ok":true,"result":{"subscriptions":[{"id":"s1","name":"Claude Max 20x","amount":{"minorUnits":20000,"currency":"USD"},"period":"monthly","paymentCardID":"card-1"}]}}
        """
        let rows = try AppCLIExchange.moneyLedgerSubscriptions(
            from: json,
            fallbackSource: "personal-ledger"
        )
        XCTAssertEqual(rows[0].amount.majorAmount, 200)
        XCTAssertEqual(rows[0].identity?.pays, "card-1")
        XCTAssertEqual(rows[0].source?.externalId, "s1")
    }

    func testCapabilitiesExchangesDefaultEmpty() throws {
        let sample = """
        {"ok":true,"result":{"name":"hermes","version":"1","cli":"/bin/h","commands":[],"state":[],"health":{"command":"x","freshness":""}}}
        """
        let caps = try Envelope.decodeResult(Capabilities.self, from: Data(sample.utf8))
        XCTAssertEqual(caps.exchanges, [])
    }

    func testCapabilitiesReadsLegacyFactsKey() throws {
        let sample = """
        {"ok":true,"result":{"name":"h","version":"1","cli":"/bin/h","commands":[],"state":[],"health":{"command":"x","freshness":""},"facts":[{"id":"app-cli-exchange.tenant.v1","command":"list --json","result":"TenantExchange"}]}}
        """
        let caps = try Envelope.decodeResult(Capabilities.self, from: Data(sample.utf8))
        XCTAssertEqual(caps.exchanges.first?.id, AppCLIExchange.ID.tenantList)
        let encoded = try JSONDecoder().decode(
            Capabilities.self,
            from: try JSONEncoder().encode(caps)
        )
        XCTAssertEqual(encoded.exchanges.count, 1)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try JSONEncoder().encode(caps)) as? [String: Any]
        )
        XCTAssertNotNil(object["exchanges"])
        XCTAssertNil(object["facts"])
    }

    func testCapabilitiesExchangesRoundTrip() throws {
        let caps = Capabilities(
            name: "subscription-ledger",
            version: "1",
            cli: "/opt/homebrew/bin/subscription-ledger",
            commands: [],
            state: [],
            health: .init(command: "x", freshness: ""),
            exchanges: [
                .init(
                    id: AppCLIExchange.ID.subscription,
                    command: "list --json",
                    result: "SubscriptionExchange"
                ),
            ]
        )
        let decoded = try JSONDecoder().decode(Capabilities.self, from: try JSONEncoder().encode(caps))
        XCTAssertEqual(decoded.exchanges.first?.id, AppCLIExchange.ID.subscription)
        XCTAssertEqual(caps.normalizedForRegistry().exchanges.count, 1)
    }

    func testUnknownIDThrows() {
        let unknown = "app-cli-exchange." + "ghost.v1"
        XCTAssertThrowsError(try AppCLIExchange.requireKnownID(unknown)) { error in
            XCTAssertEqual(error as? AppCLIExchangeError, .unknownID(unknown))
        }
        XCTAssertNoThrow(try AppCLIExchange.requireKnownID(AppCLIExchange.ID.tenantList))
    }

    func testTenantsAllBadRowsThrow() {
        let json = #"{"ok":true,"result":[{"displayName":"x"}]}"#
        XCTAssertThrowsError(try AppCLIExchange.tenants(from: json)) { error in
            XCTAssertEqual(error as? AppCLIExchangeError, .undecodableRows("tenants"))
        }
    }

    func testLegacyAmountRejectedAfterCutoff() {
        let json = """
        {"ok":true,"result":{"rows":[{"id":"y1","monthlyAmount":200,"currency":"USD"}]}}
        """
        let after = Date(timeIntervalSince1970: 1_798_848_000) // 2027-01-01
        XCTAssertThrowsError(
            try AppCLIExchange.accountBilling(from: json, now: after)
        ) { error in
            XCTAssertEqual(
                error as? AppCLIExchangeError,
                .legacyAmount(cutoff: AppCLIExchange.legacyAmountCutoffDay)
            )
        }
    }

    func testEmptyRowsAreNotUndecodable() throws {
        let json = #"{"ok":true,"result":[]}"#
        XCTAssertEqual(try AppCLIExchange.tenants(from: json), [])
    }
}
