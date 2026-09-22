import XCTest
@testable import VaultwardenKit

final class VaultURIPipelineTests: XCTestCase {
    func testBlankURI() {
        XCTAssertTrue(VaultURIPipeline.isBlankURI(""))
        XCTAssertTrue(VaultURIPipeline.isBlankURI("  "))
        XCTAssertTrue(VaultURIPipeline.isBlankURI("https://"))
        XCTAssertFalse(VaultURIPipeline.isBlankURI("https://naver.com"))
    }

    func testMergeKeepsExistingWhenIncomingEmpty() {
        let merged = VaultURIPipeline.mergedURIs(
            incoming: [],
            existing: ["https://nid.naver.com/nidlogin.login"]
        )
        XCTAssertEqual(merged, ["https://nid.naver.com/nidlogin.login"])
    }

    func testMergePrefersIncoming() {
        let merged = VaultURIPipeline.mergedURIs(
            incoming: ["https://example.com"],
            existing: ["https://old.example"]
        )
        XCTAssertEqual(merged, ["https://example.com"])
    }

    func testLoginNeedsURI() {
        var empty = VaultItem(type: 1, name: "네이버")
        XCTAssertTrue(empty.needsLoginURI)
        empty.loginURIs = ["https://nid.naver.com"]
        XCTAssertFalse(empty.needsLoginURI)
        XCTAssertEqual(empty.uri, "https://nid.naver.com")
        XCTAssertEqual(empty.uris, ["https://nid.naver.com"])
        XCTAssertFalse(VaultItem(type: 2, name: "메모").needsLoginURI)
    }

    func testLoginURIsPrefersUrisOverStaleUri() {
        var item = VaultItem(type: 1, name: "구글", uri: "", uris: ["https://accounts.google.com"])
        XCTAssertFalse(item.needsLoginURI)
        XCTAssertEqual(item.loginURIs, ["https://accounts.google.com"])
        XCTAssertTrue(item.matchesLoginHost("accounts.google.com"))
        item.uri = "https://stale.example"
        item.uris = ["https://github.com"]
        XCTAssertEqual(item.loginURIs, ["https://github.com"])
        XCTAssertTrue(item.matchesLoginHost("github.com"))
        XCTAssertFalse(item.matchesLoginHost("stale.example"))
    }

    func testProposeFromBrand() {
        let item = VaultItem(type: 1, name: "네이버 Naver tex02")
        let fill = VaultURIPipeline.proposeFill(for: item)
        XCTAssertEqual(fill?.uri, "https://nid.naver.com")
    }

    func testProposeFromHostInName() {
        let item = VaultItem(type: 1, name: "주소검색 API business.juso.go.kr")
        let fill = VaultURIPipeline.proposeFill(for: item)
        XCTAssertEqual(fill?.uri, "https://business.juso.go.kr")
    }

    func testScanSplitsFillableAndBlocked() {
        let items = [
            VaultItem(id: "1", type: 1, name: "GitHub"),
            VaultItem(id: "2", type: 1, name: "키보드마에스트로"),
            VaultItem(id: "3", type: 1, name: "구글", uri: "https://accounts.google.com"),
        ]
        let snap = VaultURIPipeline.scan(items: items)
        XCTAssertEqual(snap.loginCount, 3)
        XCTAssertEqual(snap.presentCount, 1)
        XCTAssertEqual(snap.missingCount, 2)
        XCTAssertEqual(snap.fillableCount, 1)
        XCTAssertEqual(snap.blockedCount, 1)
        XCTAssertEqual(snap.rows.first { $0.itemID == "1" }?.proposedURI, "https://github.com")
        XCTAssertEqual(snap.rows.first { $0.itemID == "2" }?.fillable, false)
        XCTAssertEqual(snap.waitlistCount, 1)
        XCTAssertTrue(VaultURIPipeline.isWaitlist(items[1]))
        XCTAssertFalse(VaultURIPipeline.isWaitlist(items[0]))
        XCTAssertEqual(snap.rows.first { $0.itemID == "2" }?.reason, "에이전트 대기 — 규칙에 없음")
    }

    func testEmailDoesNotStealBrand() {
        let apple = VaultItem(
            type: 1,
            name: "[IdP][계정] 애플 Apple ID jht002@naver.com",
            username: "jht002@naver.com"
        )
        XCTAssertEqual(VaultURIPipeline.proposeFill(for: apple)?.uri, "https://appleid.apple.com")
        let doll = VaultItem(type: 1, name: "[개인][웹] 디자인돌 designdoll tex02@naver.com")
        XCTAssertEqual(VaultURIPipeline.proposeFill(for: doll)?.uri, "https://terawell.net/ko/")
    }

    func testDisplayInitialSkipsBrackets() {
        XCTAssertEqual(VaultBracketName.displayInitial(from: "[개인][웹] 굿웨어몰"), "굿")
        XCTAssertEqual(VaultBracketName.displayInitial(from: "[IdP] 구글", fallback: "https://accounts.google.com"), "구")
        XCTAssertEqual(VaultBracketName.displayInitial(from: "[개인][웹] 2 Buffer"), "B")
        XCTAssertEqual(VaultBracketName.listTitle(from: "[개인][웹] 볼터 urit245@gmail.com"), "볼터")
        XCTAssertEqual(VaultBracketName.hostLabel(from: "https://www.goodwearmall.com/path"), "goodwearmall.com")
    }

    func testNormalizedURIListSplitsLines() {
        XCTAssertEqual(
            VaultURIPipeline.normalizedURIList("example.com\nhttps://other.io"),
            ["https://example.com", "https://other.io"]
        )
    }

    func testExpandedURIListAddsApex() {
        XCTAssertEqual(
            VaultURIPipeline.expandedURIList(["https://nid.naver.com"]),
            ["https://nid.naver.com", "https://naver.com", "https://www.naver.com"]
        )
        XCTAssertEqual(
            VaultURIPipeline.expandedURIList(["https://naver.com"]),
            ["https://naver.com", "https://www.naver.com"]
        )
        XCTAssertEqual(
            VaultURIPipeline.expandedURIList(["https://www.example.com"]),
            ["https://www.example.com", "https://example.com"]
        )
        XCTAssertEqual(
            VaultURIPipeline.expandedURIList(["https://business.juso.go.kr"]),
            ["https://business.juso.go.kr", "https://juso.go.kr", "https://www.juso.go.kr"]
        )
        XCTAssertEqual(
            VaultURIPipeline.expandedURIList([
                "https://www.dhlottery.co.kr/user.do?method=login",
            ]),
            [
                "https://www.dhlottery.co.kr/user.do?method=login",
                "https://www.dhlottery.co.kr",
                "https://dhlottery.co.kr",
            ]
        )
        let alreadyFour = [
            "https://a.example.com",
            "https://b.example.com",
            "https://c.example.com",
            "https://d.example.com",
        ]
        XCTAssertEqual(VaultURIPipeline.expandedURIList(alreadyFour), alreadyFour)
        XCTAssertEqual(
            Set(VaultURIPipeline.expandScan(items: [
                VaultItem(id: "1", type: 1, name: "네이버", uri: "https://nid.naver.com"),
                VaultItem(id: "2", type: 1, name: "이미루트", uri: "https://example.com"),
            ]).rows.map(\.itemID)),
            ["1", "2"]
        )
    }

    func testApplyAdoptionStampsLedgerAndHostTag() {
        var item = VaultItem(id: "1", type: 1, name: "네이버", uri: "https://nid.naver.com")
        item = VaultURIPipeline.applyAdoption(item)
        XCTAssertEqual(item.loginURIs, [
            "https://nid.naver.com", "https://naver.com", "https://www.naver.com",
        ])
        XCTAssertTrue(item.tags.contains("naver.com"))
        XCTAssertEqual(VaultURIPipeline.ledgerVersion(of: item), 3)
        XCTAssertNotNil(item.fields.first { $0.name == VaultURIPipeline.ledgerFieldName })
        XCTAssertNil(VaultURIPipeline.adoptedIfNeeded(item))
        XCTAssertTrue(VaultURIPipeline.expandScan(items: [item]).rows.isEmpty)
    }

    func testDraftPromotesBlockedToFillable() {
        let items = [VaultItem(id: "2", type: 1, name: "키보드마에스트로")]
        let snap = VaultURIPipeline.scan(items: items)
        let filled = VaultURIPipeline.applyDrafts(snap, drafts: ["2": "https://www.keyboardmaestro.com"])
        XCTAssertEqual(filled.fillableCount, 1)
        XCTAssertEqual(filled.blockedCount, 0)
    }

    func testSanitizeDropsFakeHTTPSBesideAppScheme() {
        XCTAssertEqual(
            VaultURIPipeline.sanitizedURIList([
                "androidapp://com.server.auditor.ssh.client",
                "https://www.ssh.client",
            ]),
            ["androidapp://com.server.auditor.ssh.client"]
        )
        XCTAssertEqual(
            VaultURIPipeline.expandedURIList(["androidapp://com.alibaba.aliexpresshd"]),
            ["androidapp://com.alibaba.aliexpresshd"]
        )
        XCTAssertEqual(
            VaultURIPipeline.sanitizedURIList([
                "androidapp://com.netflix.mediaclient",
                "https://www.netflix.com",
            ]),
            ["androidapp://com.netflix.mediaclient", "https://www.netflix.com"]
        )
        XCTAssertEqual(
            VaultURIPipeline.sanitizedURIList([
                "https://portainer.local.ranode.net",
                "https://ranode.net",
                "https://www.ranode.net",
            ]),
            ["https://portainer.local.ranode.net"]
        )
        XCTAssertFalse(VaultURIPipeline.isPublicWebURI("https://www.ssh.client"))
        XCTAssertTrue(VaultURIPipeline.isAppScheme("androidapp://com.server.auditor.ssh.client"))
    }

    func testWantedBrandBeatsWantedDotComInName() {
        let item = VaultItem(type: 1, name: "[개인][웹] 원티드 wanted.com")
        XCTAssertEqual(VaultURIPipeline.proposeFromName(item)?.uri, "https://www.wanted.co.kr")
        var empty = VaultItem(id: "w", type: 1, name: "원티드")
        empty = VaultURIPipeline.applyAdoption(empty)
        XCTAssertTrue(empty.loginURIs.contains("https://www.wanted.co.kr"))
    }

    func testInfrastructureLoginsRehomeToNotes() {
        let ssh = VaultItem(
            id: "ssh",
            type: 1,
            name: "[개인][인프라] 철물아지트 SSH",
            username: "root",
            password: "secret",
            uri: "https://220.72.222.155"
        )
        XCTAssertTrue(VaultURIPipeline.shouldRehomeToNote(ssh))
        XCTAssertNil(VaultURIPipeline.adoptedIfNeeded(ssh))
        let note = VaultURIPipeline.noteFromLogin(ssh)
        XCTAssertEqual(note.type, 2)
        XCTAssertTrue(note.notes.contains("아이디: root"))
        XCTAssertTrue(note.notes.contains("호스트: https://220.72.222.155"))
        XCTAssertTrue(note.tags.contains("SSH"))
        XCTAssertFalse(note.fields.contains { $0.name == VaultURIPipeline.ledgerFieldName })

        let local = VaultItem(id: "wp", type: 1, name: "워드프레스", uri: "http://blog.local")
        XCTAssertFalse(VaultURIPipeline.shouldRehomeToNote(local))
        let router = VaultItem(id: "rt", type: 1, name: "공유기", uri: "http://192.168.0.1")
        XCTAssertTrue(VaultURIPipeline.shouldRehomeToNote(router))
        let localNet = VaultItem(id: "pn", type: 1, name: "Portainer", uris: [
            "https://portainer.local.ranode.net",
            "https://ranode.net",
        ])
        XCTAssertFalse(VaultURIPipeline.shouldRehomeToNote(localNet))
        let pve = VaultItem(id: "pve", type: 1, name: "192.168.2.50 root", uris: [
            "https://192.168.2.50:8006",
            "https://50.internal.kr",
            "https://internal.kr",
        ])
        XCTAssertFalse(VaultURIPipeline.shouldRehomeToNote(pve))
        let app = VaultItem(
            id: "app",
            type: 1,
            name: "SSH Client",
            uris: ["androidapp://com.server.auditor.ssh.client"]
        )
        XCTAssertFalse(VaultURIPipeline.shouldRehomeToNote(app))
        XCTAssertEqual(
            Set(VaultURIPipeline.rehomeScan(items: [ssh, local, router, localNet, pve, app]).rows.map(\.itemID)),
            ["rt", "ssh"]
        )
    }

    func testJunkHostIsNotAdoptedAsWeb() {
        let lol = VaultItem(id: "lol", type: 1, name: "롤", uri: "https://jungright2")
        let adopted = VaultURIPipeline.applyAdoption(lol)
        XCTAssertEqual(adopted.loginURIs, ["https://jungright2"])
        XCTAssertFalse(adopted.loginURIs.contains(where: { $0.contains("leagueoflegends") }))
        XCTAssertEqual(VaultPlacement.classify(lol).network, "미분류")
    }
}
