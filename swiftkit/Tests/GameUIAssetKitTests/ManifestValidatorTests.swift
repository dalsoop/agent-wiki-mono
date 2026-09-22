import Foundation
import XCTest
@testable import GameUIAssetKit

final class ManifestValidatorTests: XCTestCase {
    func testValidFixtureHasNoDiagnostics() throws {
        XCTAssertEqual(try validateFixture("valid-world-map.json"), [])
    }

    func testInvalidFixturesReturnStableDiagnosticCodes() throws {
        let expectations: [(String, GameUIManifestDiagnostic.Code)] = [
            ("invalid-reference-runtime.json", .referenceInRuntime),
            ("invalid-baked-meter.json", .dynamicValueBaked),
            ("invalid-duplicate-component.json", .duplicateComponentHash),
            ("invalid-missing-action.json", .missingAction),
        ]

        for (fixture, code) in expectations {
            let diagnostics = try validateFixture(fixture)
            XCTAssertTrue(
                diagnostics.contains { $0.code == code },
                "Expected \(code.rawValue) for \(fixture), got \(diagnostics)"
            )
        }
    }

    func testUnsupportedSchemaReturnsGUI001() {
        let diagnostics = validate(manifest(schemaVersion: 99))
        XCTAssertEqual(diagnostics.map(\.code), [.unsupportedSchema])
        XCTAssertEqual(diagnostics.first?.code.rawValue, "GUI001_UNSUPPORTED_SCHEMA")
    }

    func testMissingComponentReturnsGUI003() {
        let orphan = instance(id: "orphan", componentID: "not-defined")
        let diagnostics = validate(manifest(instances: [orphan]))
        XCTAssertEqual(diagnostics.map(\.code), [.missingComponent])
    }

    func testBlankAccessibilityLabelReturnsGUI007() {
        let component = imageComponent(id: "map")
        let map = instance(id: "map-instance", componentID: component.id)
        let interaction = GameUIInteraction(
            instanceID: map.id,
            actionID: "world-map.select-territory",
            hitShape: GameUIHitShape(kind: .rectangle),
            accessibilityLabel: "   "
        )
        let diagnostics = validate(
            manifest(components: [component], instances: [map], interactions: [interaction])
        )
        XCTAssertEqual(diagnostics.map(\.code), [.missingAccessibilityLabel])
    }

    func testEscapingAssetPathReturnsGUI008() {
        let component = imageComponent(id: "escaped", path: "../secret.png")
        let diagnostics = validate(manifest(components: [component]))
        XCTAssertEqual(diagnostics.map(\.code), [.pathEscape])
    }

    func testOutOfBoundsInstanceReturnsGUI009() {
        let component = imageComponent(id: "panel")
        let panel = GameUIInstance(
            id: "panel-instance",
            componentID: component.id,
            frame: GameUIRect(x: 90, y: 90, width: 20, height: 20),
            anchor: GameUIAnchor(x: 0, y: 0),
            zIndex: 1
        )
        let diagnostics = validate(
            manifest(canvas: GameUICanvas(width: 100, height: 100), components: [component], instances: [panel])
        )
        XCTAssertEqual(diagnostics.map(\.code), [.outOfBounds])
    }

    private func validateFixture(_ name: String) throws -> [GameUIManifestDiagnostic] {
        let fixtureURL = fixturesRoot.appendingPathComponent(name)
        let manifest = try JSONDecoder().decode(
            GameUIScreenManifest.self,
            from: Data(contentsOf: fixtureURL)
        )
        return GameUIManifestValidator.validate(manifest, assetRoot: fixturesRoot)
    }

    private func validate(_ manifest: GameUIScreenManifest) -> [GameUIManifestDiagnostic] {
        GameUIManifestValidator.validate(manifest, assetRoot: fixturesRoot)
    }

    private var fixturesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private func manifest(
        schemaVersion: Int = 1,
        canvas: GameUICanvas = GameUICanvas(width: 1_672, height: 941),
        components: [GameUIComponent] = [],
        instances: [GameUIInstance] = [],
        bindings: [GameUIBinding] = [],
        interactions: [GameUIInteraction] = []
    ) -> GameUIScreenManifest {
        GameUIScreenManifest(
            schemaVersion: schemaVersion,
            id: "test-screen",
            canvas: canvas,
            components: components,
            instances: instances,
            bindings: bindings,
            interactions: interactions
        )
    }

    private func imageComponent(id: String, path: String? = nil) -> GameUIComponent {
        GameUIComponent(
            id: id,
            kind: .image,
            asset: GameUIAsset(
                path: path ?? "assets/\(id).png",
                sha256: String(repeating: "a", count: 64),
                provenance: GameUIAssetProvenance(classification: .component)
            )
        )
    }

    private func instance(id: String, componentID: String) -> GameUIInstance {
        GameUIInstance(
            id: id,
            componentID: componentID,
            frame: GameUIRect(x: 0, y: 0, width: 10, height: 10),
            anchor: GameUIAnchor(x: 0, y: 0),
            zIndex: 0
        )
    }
}
