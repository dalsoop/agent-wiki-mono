import XCTest
@testable import DoctorKit

final class StoreIntegrityProviderTests: XCTestCase {
    private func provider(
        tree: [String: [String]],
        contents: [String: Data] = [:]
    ) -> StoreIntegrityDoctorProvider {
        let root = URL(fileURLWithPath: "/root")
        return StoreIntegrityDoctorProvider(
            root: root,
            listDirectory: { url in
                let key = url.path == root.path ? "" : url.lastPathComponent
                return tree[key] ?? []
            },
            readFile: { url in contents[url.lastPathComponent] },
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    func testHealthyStoresProduceNoFindings() async {
        let p = provider(
            tree: ["": ["AppA"], "AppA": ["state.json"]],
            contents: ["state.json": Data(#"[{"id":"a"}]"#.utf8)]
        )
        let findings = await p.run()
        XCTAssertTrue(findings.isEmpty)
    }

    func testUnparseableStoreFailsLoudly() async {
        let p = provider(
            tree: ["": ["RightClick"], "RightClick": ["actions.json"]],
            contents: ["actions.json": Data("not json".utf8)]
        )
        let findings = await p.run()
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings[0].severity, .fail)
        XCTAssertEqual(findings[0].subject, "RightClick")
    }

    /// 읽지도 못하는 경우(권한·깨진 링크)도 같은 등급으로 잡아야 한다.
    func testUnreadableFileIsAlsoAFailure() async {
        let p = provider(tree: ["": ["AppB"], "AppB": ["state.json"]])
        let findings = await p.run()
        XCTAssertEqual(findings.map(\.severity), [.fail])
    }

    /// 격리본이 있으면 경고 — 데이터는 살렸지만 아무도 안 봤다는 뜻이다.
    func testRescuedCopiesWarnAndAreNotParsed() async {
        let p = provider(
            tree: ["": ["RightClick"], "RightClick": ["actions.json", "actions.corrupt-2026.json"]],
            contents: [
                "actions.json": Data("[]".utf8),
                "actions.corrupt-2026.json": Data("broken".utf8),
            ]
        )
        let findings = await p.run()
        XCTAssertEqual(findings.count, 1, "격리본 자체를 파싱 실패로 또 세면 안 된다")
        XCTAssertEqual(findings[0].severity, .warn)
        XCTAssertTrue(findings[0].detail.contains("actions.corrupt-2026.json"))
    }

    func testDirectoriesWithoutJSONAreIgnored() async {
        let p = provider(tree: ["": ["Empty"], "Empty": ["cache.db", "logs"]])
        let findings = await p.run()
        XCTAssertTrue(findings.isEmpty)
    }
}

extension StoreIntegrityProviderTests {
    /// 우리 앱만 본다 — 남의 앱까지 훑으면 고칠 수 없는 소음이 쌓인다.
    func testOnlyNamedAppsAreScanned() async {
        let root = URL(fileURLWithPath: "/root")
        let p = StoreIntegrityDoctorProvider(
            appNames: ["Ours"],
            root: root,
            listDirectory: { url in
                url.path == root.path ? ["Ours", "ThirdParty"] : ["state.json"]
            },
            readFile: { _ in Data("not json".utf8) }
        )
        let findings = await p.run()
        XCTAssertEqual(findings.map(\.subject), ["Ours"])
    }

    /// 스칼라 JSON(`true`, `"x"`, `1`)도 유효하다 — 손상으로 잡으면 오탐이다.
    func testScalarJSONIsValid() async {
        let root = URL(fileURLWithPath: "/root")
        for payload in ["true", "\"hello\"", "42"] {
            let p = StoreIntegrityDoctorProvider(
                root: root,
                listDirectory: { url in url.path == root.path ? ["App"] : ["flag.json"] },
                readFile: { _ in Data(payload.utf8) }
            )
            let findings = await p.run()
            XCTAssertTrue(findings.isEmpty, "\(payload) 는 유효한 JSON 이다")
        }
    }
}
