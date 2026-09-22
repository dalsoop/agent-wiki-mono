import XCTest
@testable import VaultwardenKit

final class VaultPlacementTests: XCTestCase {
    func testInternetSaaSIsPublicTenantPersonal() {
        let item = VaultItem(
            type: 1,
            name: "[개인][웹] 네이버",
            username: "tex02@naver.com",
            uri: "https://nid.naver.com"
        )
        let snap = VaultPlacement.classify(item)
        XCTAssertEqual(snap.network, "인터넷")
        XCTAssertEqual(snap.ops, "SaaS")
        XCTAssertEqual(snap.tenant, "개인")
        XCTAssertEqual(snap.owner, "tex02@naver.com")
    }

    func testNamedIntranetStaysOnPremRanode() {
        let item = VaultItem(
            id: "pn",
            type: 1,
            name: "Portainer",
            username: "admin",
            uris: ["https://portainer.local.ranode.net"]
        )
        XCTAssertFalse(VaultURIPipeline.shouldRehomeToNote(item))
        let snap = VaultPlacement.classify(item)
        XCTAssertEqual(snap.network, "인트라넷")
        XCTAssertEqual(snap.ops, "온프레미스")
        XCTAssertEqual(snap.tenant, "ranode")
        XCTAssertEqual(snap.owner, "admin")
        let stamped = VaultPlacement.apply(item)
        XCTAssertTrue(stamped.tags.contains("망:인트라넷"))
        XCTAssertTrue(stamped.tags.contains("테넌트:ranode"))
        XCTAssertEqual(stamped.fields.first { $0.name == VaultPlacement.tenantField }?.value, "ranode")
        XCTAssertNil(VaultPlacement.appliedIfNeeded(stamped))
    }

    func testHomeRouterTenant() {
        let item = VaultItem(type: 1, name: "공유기", uri: "http://192.168.0.1")
        XCTAssertEqual(VaultPlacement.classify(item).tenant, "집")
        XCTAssertEqual(VaultPlacement.classify(item).ops, "온프레미스")
    }

    func testAppSchemeIsAppAxis() {
        let item = VaultItem(
            type: 1,
            name: "SSH Client",
            uris: ["androidapp://com.server.auditor.ssh.client"]
        )
        let snap = VaultPlacement.classify(item)
        XCTAssertEqual(snap.network, "앱")
        XCTAssertEqual(snap.ops, "앱")
    }

    func testNoteHostsFeedTenant() {
        var note = VaultItem(type: 2, name: "철물아지트 SSH", notes: "호스트: https://220.72.222.155")
        note.username = ""
        let snap = VaultPlacement.classify(note)
        XCTAssertEqual(snap.network, "인트라넷")
        XCTAssertEqual(snap.ops, "온프레미스")
    }

    func testBrowseSectionsGroupTenantAndSortIntranetFirst() {
        let naver = VaultItem(
            id: "n", type: 1, name: "[개인][웹] 네이버",
            username: "a@n.com", uri: "https://nid.naver.com"
        )
        let portainer = VaultItem(
            id: "p", type: 1, name: "Portainer",
            username: "admin", uris: ["https://portainer.local.ranode.net"]
        )
        let stamped = [VaultPlacement.apply(naver), VaultPlacement.apply(portainer)]
        let sections = VaultPlacement.browseSections(stamped, group: .tenant)
        XCTAssertEqual(sections.map(\.title), ["ranode", "개인"])
        XCTAssertEqual(sections[0].items.map(\.id), ["p"])
        XCTAssertEqual(VaultPlacement.browseChips(stamped[1]), ["인트라넷", "ranode"])
        XCTAssertEqual(VaultPlacement.browseChips(stamped[0]), [])
        XCTAssertTrue(VaultPlacement.isMachineField(VaultPlacement.netField))
        XCTAssertTrue(VaultPlacement.isMachineField(VaultURIPipeline.ledgerFieldName))
        XCTAssertTrue(VaultPlacement.isMachineField(VaultItem.tagFieldName))
        XCTAssertFalse(VaultPlacement.isMachineField("메모"))
        XCTAssertEqual(
            VaultPlacement.browseSections(stamped, group: .network).map(\.title),
            ["인트라넷", "인터넷"]
        )
    }
}
