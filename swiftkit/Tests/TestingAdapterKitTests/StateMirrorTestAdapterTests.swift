import XCTest
import Foundation
@testable import TestingAdapterKit

final class StateMirrorTestAdapterTests: XCTestCase {

    // MARK: - Test Models

    struct SampleAppState: Codable, Equatable, Sendable {
        let isBusy: Bool
        let state: String
        let progress: Double
    }

    // MARK: - Sandbox Integration & Inspection Tests

    func testInitializationAndFileExistence() throws {
        try TestSandbox.withSandbox(prefix: "statemirror-init-test") { sandbox in
            let adapter = StateMirrorTestAdapter(sandbox: sandbox, slug: "demo-app")

            XCTAssertFalse(adapter.exists)
            XCTAssertEqual(adapter.slug, "demo-app")
            XCTAssertTrue(adapter.fileURL.path.contains("demo-app.json"))

            // 파일 작성 후 존재 확인
            try adapter.writeRawState(["isBusy": true, "state": "booting"])
            XCTAssertTrue(adapter.exists)

            let rawState = try adapter.readRawState()
            XCTAssertEqual(rawState["isBusy"] as? Bool, true)
            XCTAssertEqual(rawState["state"] as? String, "booting")

            // 삭제 확인
            adapter.clear()
            XCTAssertFalse(adapter.exists)
        }
    }

    // MARK: - Async State Waiting Tests

    func testWaitUntilReadyWithIsBusyTransition() async throws {
        try await TestSandbox.withSandbox(prefix: "statemirror-ready-test") { sandbox in
            let adapter = StateMirrorTestAdapter(sandbox: sandbox, slug: "busy-app")

            // 초기 상태: isBusy = true
            try adapter.writeRawState(["isBusy": true, "state": "processing"])

            // 비동기로 40ms 후 isBusy = false 업데이트
            Task {
                try? await Task.sleep(nanoseconds: 40_000_000)
                try? adapter.writeRawState(["isBusy": false, "state": "idle"])
            }

            let finalState = try await adapter.waitUntilReady(timeout: 1.5, pollInterval: 0.02)
            XCTAssertEqual(finalState["isBusy"] as? Bool, false)
            XCTAssertEqual(finalState["state"] as? String, "idle")
        }
    }

    func testWaitUntilStateCodable() async throws {
        try await TestSandbox.withSandbox(prefix: "statemirror-codable-test") { sandbox in
            let adapter = StateMirrorTestAdapter(sandbox: sandbox, slug: "codable-app")

            let initialState = SampleAppState(isBusy: true, state: "loading", progress: 0.1)
            try adapter.writeState(initialState)

            Task {
                try? await Task.sleep(nanoseconds: 40_000_000)
                let readyState = SampleAppState(isBusy: false, state: "ready", progress: 1.0)
                try? adapter.writeState(readyState)
            }

            let result = try await adapter.waitUntilState(
                timeout: 1.5,
                pollInterval: 0.02,
                as: SampleAppState.self
            ) { state in
                !state.isBusy && state.state == "ready"
            }

            XCTAssertEqual(result.isBusy, false)
            XCTAssertEqual(result.state, "ready")
            XCTAssertEqual(result.progress, 1.0)
        }
    }

    func testWaitUntilValueForKey() async throws {
        try await TestSandbox.withSandbox(prefix: "statemirror-value-test") { sandbox in
            let adapter = StateMirrorTestAdapter(sandbox: sandbox, slug: "value-app")

            try adapter.writeRawState(["counter": 0])

            Task {
                try? await Task.sleep(nanoseconds: 30_000_000)
                try? adapter.writeRawState(["counter": 42])
            }

            let result = try await adapter.waitUntilValue(
                forKey: "counter",
                equals: 42,
                timeout: 1.5,
                pollInterval: 0.02
            )

            XCTAssertEqual(result["counter"] as? Int, 42)
        }
    }

    func testWaitUntilJSONPredicate() async throws {
        try await TestSandbox.withSandbox(prefix: "statemirror-json-test") { sandbox in
            let adapter = StateMirrorTestAdapter(sandbox: sandbox, slug: "json-app")

            try adapter.writeRawState(["step": 1, "done": false])

            Task {
                try? await Task.sleep(nanoseconds: 30_000_000)
                try? adapter.writeRawState(["step": 3, "done": true])
            }

            let result = try await adapter.waitUntilJSON(
                timeout: 1.5,
                pollInterval: 0.02
            ) { json in
                json["step"] as? Int == 3 && json["done"] as? Bool == true
            }

            XCTAssertEqual(result["step"] as? Int, 3)
            XCTAssertEqual(result["done"] as? Bool, true)
        }
    }

    // MARK: - Timeout & Error Diagnostics Tests

    func testWaitTimeoutThrowsStateMirrorWaitTimeoutError() async throws {
        try await TestSandbox.withSandbox(prefix: "statemirror-timeout-test") { sandbox in
            let adapter = StateMirrorTestAdapter(sandbox: sandbox, slug: "stuck-app")
            try adapter.writeRawState(["isBusy": true, "state": "stuck_forever"])

            do {
                _ = try await adapter.waitUntilReady(timeout: 0.1, pollInterval: 0.02)
                XCTFail("타임아웃 시 StateMirrorWaitTimeoutError가 발생해야 합니다.")
            } catch let error as StateMirrorWaitTimeoutError {
                XCTAssertEqual(error.slug, "stuck-app")
                XCTAssertTrue(error.fileURL.path.contains("stuck-app.json"))
                XCTAssertTrue(error.description.contains("did not satisfy"))
                XCTAssertTrue(error.description.contains("stuck_forever"))
            } catch {
                XCTFail("예상치 못한 에러: \(error)")
            }
        }
    }

    // MARK: - Lifecycle Waiting Tests

    func testWaitUntilFileExistsAndRemoved() async throws {
        try await TestSandbox.withSandbox(prefix: "statemirror-lifecycle-test") { sandbox in
            let adapter = StateMirrorTestAdapter(sandbox: sandbox, slug: "lifecycle-app")

            // 파일 생성 비동기 대기
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000)
                try? adapter.writeRawState(["status": "created"])
            }

            try await adapter.waitUntilFileExists(timeout: 1.0, pollInterval: 0.02)
            XCTAssertTrue(adapter.exists)

            // 파일 제거 비동기 대기
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000)
                adapter.clear()
            }

            try await adapter.waitUntilRemoved(timeout: 1.0, pollInterval: 0.02)
            XCTAssertFalse(adapter.exists)
        }
    }
}
