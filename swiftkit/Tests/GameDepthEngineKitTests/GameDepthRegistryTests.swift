import Foundation
import GameDepthEngineKit
import XCTest

final class GameDepthRegistryTests: XCTestCase {
  func testScanFindsNestedDepthsInStableIDOrder() throws {
    let project = try TemporaryDepthProject()
    try project.writeDepth(id: "world-map")
    try project.writeDepth(id: "engine-overview")

    let records = GameDepthRegistry(projectRoot: project.root).scan()

    XCTAssertEqual(records.map(\.manifest.id), ["engine-overview", "world-map"])
    XCTAssertTrue(records.allSatisfy(\.diagnostics.isEmpty))
  }

  func testValidationReportsMissingFilesWrongCanvasAndDuplicateIDs() throws {
    let project = try TemporaryDepthProject()
    try project.writeDepth(id: "same", directory: "a", canvasWidth: 1366)
    try project.writeDepth(id: "same", directory: "b", includeFixture: false)

    let records = GameDepthRegistry(projectRoot: project.root).scan()
    let codes = Set(records.flatMap(\.diagnostics).map(\.code))

    XCTAssertTrue(codes.contains(.invalidCanvas))
    XCTAssertTrue(codes.contains(.missingFixture))
    XCTAssertTrue(codes.contains(.duplicateID))
  }

  func testMalformedDepthIsReturnedAsDiagnosticInsteadOfBeingDropped() throws {
    let project = try TemporaryDepthProject()
    let directory = project.root.appendingPathComponent("Depths/broken", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: directory.appendingPathComponent("depth.json"))

    let records = GameDepthRegistry(projectRoot: project.root).scan()

    XCTAssertEqual(records.count, 1)
    XCTAssertEqual(records[0].diagnostics.first?.code, .malformedManifest)
  }
}

private final class TemporaryDepthProject {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("game-depth-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  deinit { try? FileManager.default.removeItem(at: root) }

  func writeDepth(
    id: String,
    directory: String? = nil,
    canvasWidth: Int = 1920,
    includeFixture: Bool = true
  ) throws {
    let depthDirectory =
      root
      .appendingPathComponent("Depths", isDirectory: true)
      .appendingPathComponent(directory ?? id, isDirectory: true)
    try FileManager.default.createDirectory(at: depthDirectory, withIntermediateDirectories: true)

    let depth: [String: Any] = [
      "schemaVersion": 1,
      "id": id,
      "displayName": id,
      "canvas": "game-1920x1080",
      "screen": "screen.json",
      "fixture": "fixture.json",
      "shell": "test-shell",
      "entryAction": "\(id).open",
      "requiredCapabilities": [],
    ]
    try JSONSerialization.data(withJSONObject: depth, options: [.prettyPrinted])
      .write(to: depthDirectory.appendingPathComponent("depth.json"))

    let screen: [String: Any] = [
      "schemaVersion": 1,
      "id": id,
      "canvas": ["width": canvasWidth, "height": 1080],
      "components": [], "instances": [], "bindings": [], "interactions": [],
    ]
    try JSONSerialization.data(withJSONObject: screen, options: [.prettyPrinted])
      .write(to: depthDirectory.appendingPathComponent("screen.json"))

    if includeFixture {
      try Data("{}".utf8).write(to: depthDirectory.appendingPathComponent("fixture.json"))
    }
  }
}
