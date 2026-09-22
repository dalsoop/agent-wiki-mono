import XCTest
@testable import DalKit

final class DalKitTests: XCTestCase {
    func testTenantParseStripsPrefixForSlug() throws {
        let t = try DalTenant.parse("tenant:personal")
        XCTAssertEqual(t.slug, "personal")
        XCTAssertEqual(t.canonical, "tenant:personal")
        let w = try DalTenant.parse("wife")
        XCTAssertEqual(w.slug, "wife")
        XCTAssertEqual(w.canonical, "wife")
    }

    func testViewpointRejectsThird() {
        XCTAssertThrowsError(try DalViewpoint.requireFirst("third"))
        XCTAssertEqual(try? DalViewpoint.requireFirst("first"), "first")
        XCTAssertFalse(DalViewpoint.isFirst("unknown"))
    }

    func testPersonGrammar() {
        XCTAssertTrue(DalPersonGrammar.looksFirstPerson("나는 1993년생이다"))
        XCTAssertTrue(DalPersonGrammar.looksThirdPerson("윤정한은 1993년생이다"))
        XCTAssertFalse(DalPersonGrammar.looksThirdPerson("나는 피곤하다"))
    }

    func testDataDirectoryNotNestedUnderOtherTenant() throws {
        let t = try DalTenant.parse("tenant:wife")
        let url = DalTenant.dataDirectory(app: "dal-energy-organ", tenant: t, homeDirectory: "/tmp/home")
        XCTAssertEqual(
            url.path,
            "/tmp/home/.dal/dal-energy-organ/tenants/wife"
        )
        XCTAssertFalse(url.path.contains("/personal/"))
    }
}
