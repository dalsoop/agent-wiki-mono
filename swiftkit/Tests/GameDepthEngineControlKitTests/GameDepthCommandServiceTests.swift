import Foundation
import GameDepthEngineControlKit
import XCTest

final class GameDepthCommandServiceTests: XCTestCase {
  func testStatusStartsAtRevisionZeroWithoutCreatingRuntimeState() throws {
    let project = try TemporaryControlProject()
    let service = GameDepthCommandService(projectRoot: project.root)

    let response = try service.execute(.init(command: .status))

    XCTAssertTrue(response.ok)
    XCTAssertEqual(response.state?.revision, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: project.runtimeStateURL.path))
  }

  func testPauseMutatesOnceAndIdempotencyReplayDoesNotAdvanceRevision() throws {
    let project = try TemporaryControlProject()
    let service = GameDepthCommandService(projectRoot: project.root)
    let request = GameDepthCommandRequest(
      command: .pause,
      expectedRevision: 0,
      idempotencyKey: "pause-once",
      arguments: ["paused": "true"]
    )

    let first = try service.execute(request)
    let replay = try service.execute(request)

    XCTAssertEqual(first.state?.revision, 1)
    XCTAssertEqual(first.state?.isPaused, true)
    XCTAssertEqual(replay.state?.revision, 1)
    XCTAssertTrue(replay.replayed)
    XCTAssertTrue(FileManager.default.fileExists(atPath: project.runtimeStateURL.path))
  }

  func testStaleRevisionReturnsConflictWithoutMutation() throws {
    let project = try TemporaryControlProject()
    let service = GameDepthCommandService(projectRoot: project.root)
    _ = try service.execute(.init(command: .step, expectedRevision: 0, arguments: ["hours": "1"]))

    let stale = try service.execute(
      .init(command: .speed, expectedRevision: 0, arguments: ["value": "2"]))

    XCTAssertFalse(stale.ok)
    XCTAssertEqual(stale.error?.code, "GDE409_REVISION_CONFLICT")
    XCTAssertEqual(try service.execute(.init(command: .status)).state?.revision, 1)
  }

  func testDryRunReturnsProposedStateWithoutPersistingIt() throws {
    let project = try TemporaryControlProject()
    let service = GameDepthCommandService(projectRoot: project.root)

    let preview = try service.execute(
      .init(command: .speed, dryRun: true, expectedRevision: 0, arguments: ["value": "2"])
    )

    XCTAssertEqual(preview.state?.revision, 1)
    XCTAssertEqual(preview.state?.speed, .fast)
    XCTAssertEqual(try service.execute(.init(command: .status)).state?.revision, 0)
  }

  func testListAndValidateUseTheSharedDepthRegistry() throws {
    let project = try TemporaryControlProject()
    try project.writeValidDepth(id: "world-map")
    let service = GameDepthCommandService(projectRoot: project.root)

    let listed = try service.execute(.init(command: .list))
    let validated = try service.execute(.init(command: .validate))

    XCTAssertEqual(listed.depths?.map(\.manifest.id), ["world-map"])
    XCTAssertTrue(validated.ok)
    XCTAssertEqual(validated.diagnostics, [])
  }

  func testValidateDepthIDFiltersOtherDepthFailuresAndMissingIDIsTyped() throws {
    let project = try TemporaryControlProject()
    try project.writeValidDepth(id: "world-map")
    let broken = project.root.appendingPathComponent("Depths/broken", isDirectory: true)
    try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: broken.appendingPathComponent("depth.json"))
    let service = GameDepthCommandService(projectRoot: project.root)

    let selected = try service.execute(
      .init(command: .validate, arguments: ["depth": "world-map"])
    )
    let missing = try service.execute(
      .init(command: .validate, arguments: ["depth": "missing"])
    )

    XCTAssertTrue(selected.ok)
    XCTAssertEqual(selected.depths?.map(\.manifest.id), ["world-map"])
    XCTAssertFalse(missing.ok)
    XCTAssertEqual(missing.error?.code, "GDE404_DEPTH_NOT_FOUND")
  }

  func testStepAndSnapshotCreateTraceableArtifacts() throws {
    let project = try TemporaryControlProject()
    let service = GameDepthCommandService(projectRoot: project.root)

    let step = try service.execute(.init(command: .step, arguments: ["hours": "3"]))
    let snapshot = try service.execute(.init(command: .snapshot))

    XCTAssertEqual(step.state?.tick, 3)
    XCTAssertEqual(snapshot.state?.revision, 2)
    XCTAssertTrue(FileManager.default.fileExists(atPath: project.traceURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: project.snapshotURL(revision: 2).path))
    let traceLines = try String(contentsOf: project.traceURL, encoding: .utf8)
      .split(separator: "\n")
    XCTAssertEqual(traceLines.count, 2)
    for line in traceLines {
      XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
    }
  }

  func testIndependentServiceInstancesSerializeConcurrentMutations() async throws {
    let project = try TemporaryControlProject()
    let root = project.root

    let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
      for _ in 0..<8 {
        group.addTask {
          let service = GameDepthCommandService(projectRoot: root)
          return (try? service.execute(.init(command: .step, arguments: ["hours": "1"])).ok)
            == true
        }
      }
      var values: [Bool] = []
      for await result in group { values.append(result) }
      return values
    }

    XCTAssertTrue(results.allSatisfy { $0 })
    let state = try GameDepthCommandService(projectRoot: root)
      .execute(.init(command: .status))
      .state
    XCTAssertEqual(state?.revision, 8)
    XCTAssertEqual(state?.tick, 8)
  }
}

private final class TemporaryControlProject {
  let root: URL

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("game-control-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  deinit { try? FileManager.default.removeItem(at: root) }

  var runtimeRoot: URL { root.appendingPathComponent(".game-depth-engine", isDirectory: true) }
  var runtimeStateURL: URL { runtimeRoot.appendingPathComponent("runtime.json") }
  var traceURL: URL { runtimeRoot.appendingPathComponent("commands.jsonl") }
  func snapshotURL(revision: Int) -> URL {
    runtimeRoot.appendingPathComponent("snapshots/revision-\(revision).json")
  }

  func writeValidDepth(id: String) throws {
    let directory = root.appendingPathComponent("Depths/\(id)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let depth: [String: Any] = [
      "schemaVersion": 1, "id": id, "displayName": id,
      "canvas": "game-1920x1080", "screen": "screen.json", "fixture": "fixture.json",
      "shell": "test", "entryAction": "\(id).open", "requiredCapabilities": [],
    ]
    let screen: [String: Any] = [
      "schemaVersion": 1, "id": id, "canvas": ["width": 1920, "height": 1080],
      "components": [], "instances": [], "bindings": [], "interactions": [],
    ]
    try JSONSerialization.data(withJSONObject: depth).write(
      to: directory.appendingPathComponent("depth.json"))
    try JSONSerialization.data(withJSONObject: screen).write(
      to: directory.appendingPathComponent("screen.json"))
    try Data("{}".utf8).write(to: directory.appendingPathComponent("fixture.json"))
  }
}
