import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// 병합 개정 — 같은 객체에서 갈라진 두 개정을 한 개정이 함께 대체한다(git 병합 커밋의 부모 둘처럼).
@Suite struct MergeSupersedesTests {
    private func makeWorld() -> (root: URL, store: LedgerStore, objectsDir: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-merge-\(UUID())", isDirectory: true)
        return (root, LedgerStore(root: root), root.appendingPathComponent("objects"))
    }

    /// base → (left, right) 로 갈라진 뒤 merge 가 둘을 대체한다.
    private func forked(_ store: LedgerStore) throws -> (base: LedgerObject, left: LedgerObject, right: LedgerObject, merge: LedgerObject) {
        let base = try store.publish(author: "t", title: "결정: 병합 시험", type: "decision", body: "원본")
        let left = try store.publish(author: "a", title: "결정: 병합 시험", type: "decision", body: "왼쪽",
                                     extras: LedgerPublishExtras(supersedes: base.id))
        let right = try store.publish(author: "b", title: "결정: 병합 시험", type: "decision", body: "오른쪽",
                                      extras: LedgerPublishExtras(supersedes: base.id))
        let merge = try store.publish(author: "c", title: "결정: 병합 시험", type: "decision", body: "왼쪽+오른쪽",
                                      extras: LedgerPublishExtras(supersedes: right.id, supersedesAlso: [left.id]))
        return (base, left, right, merge)
    }

    @Test func aMergeRevisionLeavesOneHead() throws {
        let world = makeWorld()
        defer { try? FileManager.default.removeItem(at: world.root) }
        let (_, left, right, merge) = try forked(world.store)

        let heads = world.store.heads(world.store.scan()).filter { $0.title == "결정: 병합 시험" }
        #expect(heads.map(\.id) == [merge.id])
        #expect(merge.allSupersedes == [right.id, left.id])

        let index = LedgerIndex(root: world.root)
        _ = index.sync(objectsDir: world.objectsDir)
        #expect(index.resolveIDs("결정: 병합 시험") == [merge.id])
        #expect(index.mergeParents(of: merge.id) == [left.id])
    }

    @Test func verifyAcceptsMultipleParentsAndCatchesAMissingOne() throws {
        let world = makeWorld()
        defer { try? FileManager.default.removeItem(at: world.root) }
        let (base, left, _, merge) = try forked(world.store)
        #expect(world.store.verify().isEmpty)

        // 병합 부모 줄도 코어라 바꾸면 코어 변조, 없는 부모를 가리키면 참조 오류다.
        let enumerator = FileManager.default.enumerator(at: world.objectsDir, includingPropertiesForKeys: nil)
        let url = try #require((enumerator?.allObjects as? [URL])?.first { $0.lastPathComponent == "\(merge.id).md" })
        let text = try String(contentsOf: url, encoding: .utf8)
        try text.replacingOccurrences(of: "supersedes-also: \(left.id)", with: "supersedes-also: \(base.id.dropLast())0")
            .write(to: url, atomically: true, encoding: .utf8)
        let problems = world.store.verify().map(\.problem)
        #expect(problems.contains { $0.hasPrefix("코어 변조") })
        #expect(problems.contains { $0.hasPrefix("없는 객체 참조") })
    }

    @Test func historyFollowsBothBranches() throws {
        let world = makeWorld()
        defer { try? FileManager.default.removeItem(at: world.root) }
        let (base, left, right, merge) = try forked(world.store)
        let objects = world.store.scan()

        #expect(world.store.lineage(objects, of: merge.id).map(\.id) == [merge.id, right.id, base.id])
        let branches = world.store.mergedBranches(objects, of: merge.id)
        #expect(branches.map(\.parent) == [left.id])
        #expect(branches.first?.chain.map(\.id) == [left.id, base.id])
    }

    /// 옛 판 CLI 는 `supersedes-also:` 를 모르는 필드로 보존한다. 그렇게 읽어도 같은 id 가 나와야 verify 가
    /// 병합 개정을 코어 변조로 보지 않는다.
    @Test func olderParsersSeeTheSameIdentity() throws {
        let world = makeWorld()
        defer { try? FileManager.default.removeItem(at: world.root) }
        let (_, left, right, merge) = try forked(world.store)

        let asOldParserSees = LedgerObject(
            id: merge.id, published: merge.published, author: merge.author,
            title: merge.title, type: merge.type, body: merge.body,
            extras: LedgerObject.Extras(supersedes: right.id, unknownFields: ["supersedes-also: \(left.id)"]))
        #expect(asOldParserSees.contentID() == merge.id)

        // 부모가 하나인 객체는 줄이 하나도 늘지 않는다(기존 id 불변).
        #expect(!right.serialize().contains("supersedes-also"))
    }
}

/// 설치된 `agent-wiki publish` 가 쓰는 인자 해석(WorldScopedPublishArgs) — `--supersedes` 를 반복하면 병합이다.
@Suite struct MergeSupersedesArgsTests {
    @Test func repeatedSupersedesBecomesAMerge() {
        let fields = WorldScopedPublishArgs.parse(["publish", "--title", "t", "--supersedes", "aaa", "--supersedes", "bbb", "--supersedes", "ccc"])
        #expect(fields.supersedes == "aaa")
        #expect(fields.supersedesAlso == ["bbb", "ccc"])
        #expect(fields.allSupersedes == ["aaa", "bbb", "ccc"])
        #expect(fields.unknownOption == nil)
    }
}
