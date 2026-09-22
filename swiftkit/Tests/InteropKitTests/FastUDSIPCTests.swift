import XCTest
@testable import InteropKit

final class FastUDSIPCTests: XCTestCase {
    private var socketPath: String!
    private var server: FastUDSServer?

    override func setUp() {
        super.setUp()
        socketPath = NSTemporaryDirectory() + "test-uds-\(UUID().uuidString).sock"
    }

    override func tearDown() {
        server?.stop()
        server = nil
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        super.tearDown()
    }

    func testEchoRoundTrip() async throws {
        server = FastUDSServer(socketPath: socketPath) { data in
            return data
        }
        try server?.start()

        let client = FastUDSClient(socketPath: socketPath)
        let message = "Hello Fast UDS IPC!"
        let response = try await client.send(string: message)
        XCTAssertEqual(response, message)
    }

    func testMultipleRequests() async throws {
        server = FastUDSServer(socketPath: socketPath) { data in
            let text = String(data: data, encoding: .utf8) ?? ""
            return Data("ACK:\(text)".utf8)
        }
        try server?.start()

        let client = FastUDSClient(socketPath: socketPath)
        for i in 0..<20 {
            let msg = "req_\(i)"
            let res = try await client.send(string: msg)
            XCTAssertEqual(res, "ACK:\(msg)")
        }
    }

    func testConcurrentRequests() async throws {
        server = FastUDSServer(socketPath: socketPath) { data in
            return data
        }
        try server?.start()

        let client = FastUDSClient(socketPath: socketPath)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<30 {
                group.addTask {
                    let msg = "concurrent_\(i)"
                    let res = try await client.send(string: msg)
                    XCTAssertEqual(res, msg)
                }
            }
            try await group.waitForAll()
        }
    }

    func testLatencyUnderOneMillisecond() async throws {
        server = FastUDSServer(socketPath: socketPath) { data in
            return data
        }
        try server?.start()

        let client = FastUDSClient(socketPath: socketPath)
        // Warm-up
        _ = try await client.send(string: "warmup")

        let iterations = 100
        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            let res = try await client.send(string: "ping_\(i)")
            XCTAssertEqual(res, "ping_\(i)")
        }
        let totalElapsed = CFAbsoluteTimeGetCurrent() - start
        let avgRTTSeconds = totalElapsed / Double(iterations)
        let avgRTTMs = avgRTTSeconds * 1000.0

        XCTAssertLessThan(avgRTTSeconds, 0.001, "Average RTT should be under 1ms, got \(avgRTTMs) ms")
    }

    func testTimeout() async throws {
        server = FastUDSServer(socketPath: socketPath) { _ in
            try await Task.sleep(nanoseconds: 300_000_000)
            return Data("delayed".utf8)
        }
        try server?.start()

        let client = FastUDSClient(socketPath: socketPath, timeout: 0.05)
        do {
            _ = try await client.send(string: "hello")
            XCTFail("Expected timeout error")
        } catch let error as FastUDSError {
            XCTAssertTrue(error == .timeout || error == .readFailed(EAGAIN) || error == .readFailed(EWOULDBLOCK))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testConnectionFailureWhenServerNotRunning() async {
        let client = FastUDSClient(socketPath: socketPath)
        do {
            _ = try await client.send(string: "hello")
            XCTFail("Expected connectFailed")
        } catch let error as FastUDSError {
            if case .connectFailed = error {
                // Expected
            } else {
                XCTFail("Expected connectFailed, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
