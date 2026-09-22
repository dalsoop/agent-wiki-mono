import XCTest
import MoneyLedgerModels
@testable import MoneyLedgerModels

final class LedgerContextTests: XCTestCase {
    func testScopeIdentity() {
        XCTAssertEqual(LedgerScope.business.appName, "BusinessLedger")
        XCTAssertEqual(LedgerScope.business.slug, "business-ledger")
        XCTAssertEqual(LedgerScope.personal.appName, "PersonalLedger")
        XCTAssertEqual(LedgerScope.personal.slug, "personal-ledger")
    }

    func testStandardRootsDiffer() {
        let business = LedgerContext.standard(scope: .business, environment: [:])
        let personal = LedgerContext.standard(scope: .personal, environment: [:])
        XCTAssertNotEqual(business.databaseURL, personal.databaseURL)
        XCTAssertTrue(business.databaseURL.path.contains("BusinessLedger"))
        XCTAssertTrue(personal.databaseURL.path.contains("PersonalLedger"))
        XCTAssertTrue(business.databaseURL.path.hasSuffix("ledger.sqlite"))
    }

    func testHomeOverride() {
        let context = LedgerContext.standard(
            scope: .business,
            environment: ["BUSINESS_LEDGER_HOME": "/tmp/mf-test"]
        )
        XCTAssertEqual(context.databaseURL.path, "/tmp/mf-test/ledger.sqlite")
        // 다른 scope 의 환경변수는 영향 없음
        let personal = LedgerContext.standard(
            scope: .personal,
            environment: ["BUSINESS_LEDGER_HOME": "/tmp/mf-test"]
        )
        XCTAssertFalse(personal.databaseURL.path.contains("mf-test"))
    }

    func testVaultNaming() {
        let context = LedgerContext.standard(scope: .business, environment: [:])
        XCTAssertEqual(context.vaultKeychainService, "net.ranode.business-ledger.vault")
        XCTAssertEqual(context.masterPasswordEnvKey, "BUSINESS_LEDGER_MASTER_PASSWORD")
        XCTAssertEqual(
            context.vaultNoteName(entity: "account", id: "abc-123"),
            "ledger/business/account/abc-123"
        )
        XCTAssertEqual(context.stateMirrorApp, "business-ledger")
    }
}
