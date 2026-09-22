@testable import GameRealtimeEngineKit
import GameRealtimeProtocolKit
import GameRealtimeStateKit
import XCTest

final class FacadeTests: XCTestCase {
    func testFacadeOnlyRunIsDeterministic() async throws {
        let configuration = try GameRealtimeConfiguration()
        let initialState = CanonicalWorldState(seed: 42)
        let input = try makeInput(sequence: 7)
        let session = try GameRealtimeEngineSession(
            configuration: configuration,
            initialState: initialState
        )
        try await session.submit(input)

        for _ in 0 ..< 10_000 {
            _ = try await session.advanceOneTick()
        }
        let checkpoint = try await session.snapshot()
        XCTAssertEqual(checkpoint.tick, 10_000)

        for _ in 0 ..< 5 {
            _ = try await session.advanceOneTick()
        }
        try await session.restore(checkpoint)
        let restoredSnapshot = try await session.snapshot()
        XCTAssertEqual(restoredSnapshot, checkpoint)

        let deterministicSession = try GameRealtimeEngineSession(
            configuration: configuration,
            initialState: initialState
        )
        try await deterministicSession.submit(input)
        for _ in 0 ..< 10_000 {
            _ = try await deterministicSession.advanceOneTick()
        }
        let deterministicSnapshot =
            try await deterministicSession.snapshot()
        XCTAssertEqual(deterministicSnapshot, checkpoint)

        let ownershipSession = try GameRealtimeEngineSession(
            configuration: configuration,
            initialState: initialState
        )
        try await ownershipSession.submit(input)
        async let advancing = ownershipSession.advanceOneTick()
        var sawReentrantMutation = false
        for _ in 0 ..< 200 {
            do {
                try await ownershipSession.submit(input)
                await Task.yield()
            } catch EngineOwnershipError.reentrantMutation {
                sawReentrantMutation = true
                break
            }
        }
        _ = try await advancing
        XCTAssertTrue(
            sawReentrantMutation,
            "submit must collide with in-flight advanceOneTick"
        )

        let pausedSession = try GameRealtimeEngineSession(
            configuration: configuration,
            initialState: initialState
        )
        try await pausedSession.submit(input)
        await pausedSession.pause()
        await XCTAssertThrowsEngineError(.inactiveLifecycle(.paused)) {
            _ = try await pausedSession.advanceOneTick()
        }
        await pausedSession.resume()
        await XCTAssertThrowsEngineError(.missingInput) {
            _ = try await pausedSession.advanceOneTick()
        }
        try await pausedSession.submit(input)
        _ = try await pausedSession.advanceOneTick()

        let reentrantLifecycleSession = try GameRealtimeEngineSession(
            configuration: configuration,
            initialState: initialState
        )
        try await reentrantLifecycleSession.submit(input)
        async let lifecycleAdvance =
            reentrantLifecycleSession.advanceOneTick()
        var sawLifecycleMutation = false
        for _ in 0 ..< 200 {
            do {
                _ = try await reentrantLifecycleSession.snapshot()
                await Task.yield()
            } catch EngineOwnershipError.reentrantMutation {
                sawLifecycleMutation = true
                break
            }
        }
        XCTAssertTrue(
            sawLifecycleMutation,
            "pause must run while advanceOneTick holds the session"
        )
        await reentrantLifecycleSession.pause()
        await reentrantLifecycleSession.resume()
        _ = try await lifecycleAdvance
        await XCTAssertThrowsEngineError(.missingInput) {
            _ = try await reentrantLifecycleSession.advanceOneTick()
        }
        let lifecycleSnapshot =
            try await reentrantLifecycleSession.snapshot()
        XCTAssertEqual(lifecycleSnapshot.tick, 1)
    }

    private func makeInput(sequence: UInt64) throws -> CombatInputFrame {
        try CombatInputFrame(
            targetTick: 1,
            controlledEntity: EntityHandle(index: 0, generation: 1),
            sequence: sequence,
            source: .manual,
            move: FixedVector2(
                x: FixedPoint(rawValue: 0),
                y: FixedPoint(rawValue: 0)
            ),
            aim: FixedVector2(
                x: FixedPoint(rawValue: 1_024),
                y: FixedPoint(rawValue: 0)
            ),
            buttons: [.primaryAction]
        )
    }
}

private func XCTAssertThrowsEngineError(
    _ expected: GameRealtimeEngineError,
    _ operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("expected GameRealtimeEngineError", file: file, line: line)
    } catch {
        XCTAssertEqual(
            error as? GameRealtimeEngineError,
            expected,
            file: file,
            line: line
        )
    }
}
