import Darwin
import Foundation
import XCTest
@testable import StateMirrorKit

final class StateMirrorAtomicMutationTests: XCTestCase {
    func testExplicitRecoveryReplacesMalformedEnvelope() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-mirror-corrupt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let mirrorURL = root.appendingPathComponent("state.json")
        try Data("{not-json".utf8).write(to: mirrorURL)

        try StateMirror.mutate(
            url: mirrorURL,
            app: "fixture",
            as: AtomicFixtureState.self,
            recovery: .replaceMalformed
        ) { existing in
            XCTAssertNil(existing)
            return AtomicFixtureState(
                isAuditing: false,
                completed: 274,
                pipeline: "recovered"
            )
        }

        let result = try StateMirror.read(url: mirrorURL, as: AtomicFixtureState.self).state
        XCTAssertFalse(result.isAuditing)
        XCTAssertEqual(result.completed, 274)
        XCTAssertEqual(result.pipeline, "recovered")
    }

    func testMutationReadsTerminalStateCommittedBeforeLockAcquisition() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-mirror-mutate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let mirrorURL = root.appendingPathComponent("state.json")
        let lockURL = URL(fileURLWithPath: mirrorURL.path + ".lock")
        let lockDescriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(lockDescriptor, 0)
        XCTAssertEqual(flock(lockDescriptor, LOCK_EX), 0)

        let mutationStarted = expectation(description: "mutation task started")
        let mutation = Task.detached {
            mutationStarted.fulfill()
            try StateMirror.mutate(
                url: mirrorURL,
                app: "fixture",
                as: AtomicFixtureState.self
            ) { existing in
                var patched = existing ?? AtomicFixtureState(
                    isAuditing: false,
                    completed: 0,
                    pipeline: nil
                )
                patched.pipeline = "refreshed"
                return patched
            }
        }
        await fulfillment(of: [mutationStarted], timeout: 2)

        let terminal = AtomicFixtureEnvelope(
            app: "fixture",
            updatedAt: "2026-07-23T00:00:01Z",
            state: AtomicFixtureState(
                isAuditing: false,
                completed: 274,
                pipeline: nil
            )
        )
        try JSONEncoder().encode(terminal).write(to: mirrorURL, options: .atomic)
        XCTAssertEqual(flock(lockDescriptor, LOCK_UN), 0)
        close(lockDescriptor)

        try await mutation.value

        let result = try StateMirror.read(url: mirrorURL, as: AtomicFixtureState.self).state
        XCTAssertFalse(result.isAuditing)
        XCTAssertEqual(result.completed, 274)
        XCTAssertEqual(result.pipeline, "refreshed")
    }
}

private struct AtomicFixtureState: Codable, Sendable {
    var isAuditing: Bool
    var completed: Int
    var pipeline: String?
}

private struct AtomicFixtureEnvelope<State: Encodable>: Encodable {
    let app: String
    let updatedAt: String
    let state: State
}
