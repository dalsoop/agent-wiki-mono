import XCTest
@testable import GameSimulationStateKit

final class GameEntityRepositoryTests: XCTestCase {
    func testReparentPreservesSubtreeAndRejectsCycleWithoutMutation() throws {
        var repository = GameEntityRepository()
        try repository.add(.init(id: "parent"))
        try repository.add(.init(id: "child", parentID: "parent"))
        try repository.add(.init(id: "grandchild", parentID: "child"))
        let before = repository

        XCTAssertThrowsError(try repository.setParent(of: "parent", to: "grandchild")) {
            XCTAssertEqual(
                $0 as? GameEntityRepositoryError,
                .cycle(entityID: "parent", parentID: "grandchild")
            )
        }
        XCTAssertEqual(repository, before)
        XCTAssertEqual(repository.descendants(of: "parent"), ["child", "grandchild"])
    }

    func testSubtreeRemovalIsLeafFirstAndTagIndexStaysInSync() throws {
        var repository = GameEntityRepository()
        try repository.add(.init(id: "parent", tags: ["fortress"]))
        try repository.add(.init(id: "child", parentID: "parent", tags: ["fortress"]))

        XCTAssertEqual(try repository.removeSubtree(rootedAt: "parent"), ["child", "parent"])
        XCTAssertEqual(repository.entityIDs(tagged: "fortress"), [])
        XCTAssertEqual(repository.rootIDs, [])
    }

    func testMissingParentAndDuplicateIDAreTypedAndAtomic() throws {
        var repository = GameEntityRepository()
        try repository.add(.init(id: "hero"))
        let before = repository

        XCTAssertThrowsError(try repository.add(.init(id: "hero"))) {
            XCTAssertEqual($0 as? GameEntityRepositoryError, .duplicateID("hero"))
        }
        XCTAssertThrowsError(try repository.setParent(of: "hero", to: "missing")) {
            XCTAssertEqual($0 as? GameEntityRepositoryError, .missingParent("missing"))
        }
        XCTAssertEqual(repository, before)
    }

    func testCodableRoundTripKeepsStableRootAndChildOrder() throws {
        var repository = GameEntityRepository()
        try repository.add(.init(id: "root-b"))
        try repository.add(.init(id: "root-a"))
        try repository.add(.init(id: "child-b", parentID: "root-a"))
        try repository.add(.init(id: "child-a", parentID: "root-a"))

        let data = try JSONEncoder().encode(repository)
        let decoded = try JSONDecoder().decode(GameEntityRepository.self, from: data)

        XCTAssertEqual(decoded, repository)
        XCTAssertEqual(decoded.rootIDs, ["root-b", "root-a"])
        XCTAssertEqual(decoded.childIDs(of: "root-a"), ["child-b", "child-a"])
    }

    func testTagMutationKeepsReverseIndexInSync() throws {
        var repository = GameEntityRepository()
        try repository.add(.init(id: "hero"))
        try repository.addTag("leader", to: "hero")
        XCTAssertEqual(repository.entityIDs(tagged: "leader"), ["hero"])
        try repository.removeTag("leader", from: "hero")
        XCTAssertEqual(repository.entityIDs(tagged: "leader"), [])
    }

    func testEntityIDCanBeInjectedOrGenerated() {
        XCTAssertEqual(GameEntityID("fixture.hero").rawValue, "fixture.hero")
        XCTAssertFalse(GameEntityID.random().rawValue.isEmpty)
    }

    func testCanonicalEncodingSortsTagsAndRejectsOrphanRecords() throws {
        var repository = GameEntityRepository()
        try repository.add(.init(id: "root", tags: ["zeta", "alpha", "middle"]))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(repository)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let records = try XCTUnwrap(json["records"] as? [[String: Any]])
        XCTAssertEqual(records.first?["tags"] as? [String], ["alpha", "middle", "zeta"])

        let orphan = Data(#"{"records":[{"id":"child","parentID":"missing","tags":[]}]}"#.utf8)
        XCTAssertThrowsError(
            try JSONDecoder().decode(GameEntityRepository.self, from: orphan)
        )
    }
}
