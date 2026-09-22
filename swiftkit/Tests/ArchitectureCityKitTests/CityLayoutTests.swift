import XCTest
@testable import ArchitectureCityKit

final class CityLayoutTests: XCTestCase {
    func testUnusedStaysInSameDistrict() {
        let items = [
            CityItem(role: .controller, name: "LiveCtrl", district: "Http", face: .backend, placement: .init(weight: 40), used: true, reason: .reachable),
            CityItem(role: .controller, name: "DeadCtrl", district: "Http", face: .backend, placement: .init(weight: 10), used: false, reason: .unrouted),
            CityItem(role: .page, name: "Cart", district: "Pages", face: .frontend, placement: .init(weight: 20), used: true, reason: .rendered),
        ]
        let world = CityLayout.world(items: items)
        XCTAssertEqual(world.unusedCount, 1)
        XCTAssertEqual(world.usedCount, 2)
        XCTAssertEqual(world.buildingById[CityIdentity.make(.controller, "DeadCtrl")]?.district, "Http")
        XCTAssertEqual(world.buildingById[CityIdentity.make(.controller, "LiveCtrl")]?.district, "Http")
        XCTAssertEqual(world.buildingById[CityIdentity.make(.controller, "DeadCtrl")]?.usage, .unused)
        XCTAssertEqual(world.buildingById[CityIdentity.make(.page, "Cart")]?.face, .frontend)
    }

    func testCityItemAcceptsFlatFileAndWeight() {
        let item = CityItem(
            id: "n1",
            label: "Node",
            district: "Http",
            role: .controller,
            face: .backend,
            file: "app/Http/Live.php",
            weight: 40,
            used: true,
            reason: .reachable
        )
        XCTAssertEqual(item.file, "app/Http/Live.php")
        XCTAssertEqual(item.weight, 40)
        XCTAssertNil(item.line)
    }

    func testUnusedFilterDropsUsedLots() {
        let items = [
            CityItem(role: .model, name: "A", district: "M", face: .backend, used: true, reason: .reachable),
            CityItem(role: .model, name: "B", district: "M", face: .backend, used: false, reason: .unsurfaced),
        ]
        let world = CityLayout.world(items: items, filter: .unused)
        XCTAssertEqual(world.buildings.map(\.id), [CityIdentity.make(.model, "B")])
    }

    func testDistrictsDoNotOverlap() {
        let items = (0..<8).map { i in
            CityItem(role: .controller, name: "N\(i)", district: i < 4 ? "A" : "B", face: .backend, used: i % 2 == 0, reason: .reachable)
        }
        let world = CityLayout.world(items: items)
        for i in 0..<world.districts.count {
            for j in (i + 1)..<world.districts.count {
                XCTAssertFalse(CityLayout.districtsOverlap(world.districts[i], world.districts[j]))
            }
        }
    }

    func testCatalogResolvesAliasesAndHopPaths() {
        var catalog = CityCatalog()
        catalog.add(CityItem(role: .controller, name: "Home", district: "Http", face: .backend, used: true, reason: .reachable))
        catalog.add(CityItem(role: .page, name: "Home", district: "Pages", face: .frontend, used: true, reason: .rendered))
        catalog.aliases = ["ctrl": CityIdentity.make(.controller, "Home")]
        catalog.edges = [CityEdge(from: "ctrl", to: CityIdentity.make(.page, "Home"))]
        let world = catalog.world(
            liveIds: ["ctrl"],
            hopPaths: [["ctrl", CityIdentity.make(.page, "Home")]]
        )
        XCTAssertEqual(world.buildingById[CityIdentity.make(.controller, "Home")]?.usage, .live)
        XCTAssertEqual(world.segments.count, 1)
        XCTAssertEqual(world.particlePaths.count, 1)
    }

    func testQueryKeepsSearchHitsAndWalkExpandsMentions() {
        let items = [
            CityItem(role: .controller, name: "Home", district: "Http", face: .backend, used: true, reason: .reachable),
            CityItem(role: .job, name: "Send", district: "Jobs", face: .backend, used: false, reason: .unsurfaced),
        ]
        let filtered = CityLayout.world(items: items, query: CityQuery(text: "Send"))
        XCTAssertEqual(filtered.buildings.map(\.label), ["Send"])
        XCTAssertEqual(filtered.usedCount, 1)
        XCTAssertEqual(filtered.unusedCount, 1)
        let expanded = CityUsageWalk.expand(seeds: ["a"], outgoing: ["a": ["b"], "b": ["c"]])
        XCTAssertEqual(expanded, ["a", "b", "c"])
        XCTAssertEqual(CityMention.names(known: ["SendOrder", "Order"], in: "SendOrder::dispatch();"), ["SendOrder"])
    }
}
