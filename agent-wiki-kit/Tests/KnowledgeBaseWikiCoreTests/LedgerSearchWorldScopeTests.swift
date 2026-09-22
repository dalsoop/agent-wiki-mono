import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// `search` 가 **선택된 world 의 인덱스만** 본다는 계약.
///
/// 회귀 대상: CLI 의 인덱스 고속경로가 `store.root` 가 아니라
/// `LedgerConfig.load().rootURL`(= 기본 world) 로 인덱스를 열던 결함.
/// `--world gujo-wiki search` 가 repo 원장 index.db 를 뒤져서 **조용히 틀린 답**
/// 을 냈다 — 빈 결과가 아니라 다른 원장의 객체를 결과로 내놨다. 빈 결과라면
/// 눈에 띄었을 텐데 그럴듯한 답이 나와서 안 띄었다.
///
/// 여기서는 그 아래 계약, 즉 "인덱스는 자기 root 의 객체만 안다" 를 고정한다.
/// 두 원장을 만들어 서로의 객체가 새지 않는지 본다.
@Suite struct LedgerSearchWorldScopeTests {
    private func makeWorld(title: String, body: String) throws -> (root: URL, id: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-scope-\(UUID())", isDirectory: true)
        let store = LedgerStore(root: root)
        let object = try store.publish(author: "test", title: title, type: "concept", body: body)
        let index = LedgerIndex(root: root)
        _ = index.sync(objectsDir: root.appendingPathComponent("objects"))
        return (root, object.id)
    }

    @Test func searchIndexOnlySeesItsOwnWorld() throws {
        let alpha = try makeWorld(title: "개념: 알파고유낱말", body: "알파 본문")
        let beta = try makeWorld(title: "개념: 베타고유낱말", body: "베타 본문")
        defer {
            try? FileManager.default.removeItem(at: alpha.root)
            try? FileManager.default.removeItem(at: beta.root)
        }

        let alphaIndex = LedgerIndex(root: alpha.root)
        let betaIndex = LedgerIndex(root: beta.root)

        // 자기 것은 찾는다.
        #expect(alphaIndex.search("알파고유낱말").contains { $0.id == alpha.id })
        #expect(betaIndex.search("베타고유낱말").contains { $0.id == beta.id })

        // 남의 것은 못 찾는다 — 여기가 새면 world 격리가 깨진 것이다.
        #expect(alphaIndex.search("베타고유낱말").isEmpty)
        #expect(betaIndex.search("알파고유낱말").isEmpty)

        // 객체 수도 원장별로 독립이어야 한다.
        #expect(alphaIndex.objectCount() == 1)
        #expect(betaIndex.objectCount() == 1)
    }
}
