import Foundation
import XCTest
@testable import GameUIAssetKit

final class ManifestCodableTests: XCTestCase {
    func testDecodesKnownWorldMapManifest() throws {
        let manifest = try decodeFixture()

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.id, "ui-03-world-map")
        XCTAssertEqual(manifest.canvas, GameUICanvas(width: 1_672, height: 941))
        XCTAssertEqual(manifest.components.count, 2)
        XCTAssertEqual(manifest.instances.count, 3)
        XCTAssertEqual(manifest.bindings.count, 2)
        XCTAssertEqual(manifest.interactions.count, 1)
    }

    func testMultipleInstancesReferenceOneComponent() throws {
        let manifest = try decodeFixture()
        let meterInstances = manifest.instances.filter { $0.componentID == "meter-track-small" }

        XCTAssertEqual(meterInstances.map(\.id), ["territory-a-meter", "territory-b-meter"])
        XCTAssertEqual(Set(meterInstances.map(\.componentID)), ["meter-track-small"])
    }

    func testEncodeDecodeRoundTripPreservesManifest() throws {
        let manifest = try decodeFixture()
        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(GameUIScreenManifest.self, from: encoded)

        XCTAssertEqual(decoded, manifest)
    }

    private func decodeFixture() throws -> GameUIScreenManifest {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/valid-world-map.json")
        return try JSONDecoder().decode(
            GameUIScreenManifest.self,
            from: Data(contentsOf: fixtureURL)
        )
    }
}
