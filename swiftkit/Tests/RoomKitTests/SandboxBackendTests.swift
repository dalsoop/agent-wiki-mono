import XCTest
@testable import RoomKit

final class SandboxBackendTests: XCTestCase {
    func testDefaultIsSeatbelt() {
        XCTAssertEqual(SandboxBackend.seatbelt.rawValue, "seatbelt")
    }

    func testRoomSpecBackwardCompatibility() throws {
        // 기존 JSON 에 sandboxBackend 키가 없을 때 seatbelt 로 디코딩되어야 한다
        let json = try XCTUnwrap("""
        {
            "roomID": "550e8400-e29b-41d4-a716-446655440000",
            "tenant": "test",
            "task": "seatbelt-task",
            "verdict": "check",
            "walls": {
                "filesystem": {
                    "denyRead": [],
                    "allowRead": ["/"],
                    "allowWrite": [],
                    "denyWrite": []
                },
                "network": false,
                "unixSockets": [],
                "executables": {"mode": "hostPath"},
                "shell": "restricted",
                "writePaths": []
            }
        }
        """.data(using: .utf8))
        let spec = try JSONDecoder().decode(RoomSpec.self, from: json)
        XCTAssertEqual(spec.sandboxBackend, .seatbelt)
    }

    func testRoomSpecWithSRTBackend() throws {
        let json = try XCTUnwrap("""
        {
            "roomID": "550e8400-e29b-41d4-a716-446655440000",
            "tenant": "test",
            "task": "srt-task",
            "verdict": "check",
            "sandboxBackend": "srt",
            "walls": {
                "filesystem": {
                    "denyRead": [],
                    "allowRead": ["/"],
                    "allowWrite": [],
                    "denyWrite": []
                },
                "network": false,
                "unixSockets": [],
                "executables": {"mode": "hostPath"},
                "shell": "restricted",
                "writePaths": []
            }
        }
        """.data(using: .utf8))
        let spec = try JSONDecoder().decode(RoomSpec.self, from: json)
        XCTAssertEqual(spec.sandboxBackend, .srt)
    }

    func testRoundTrip() throws {
        let spec = RoomSpec(
            tenant: "t",
            task: "task",
            verdict: "v",
            executionPolicy: RoomExecutionPolicy(sandboxBackend: .srt)
        )
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(RoomSpec.self, from: data)
        XCTAssertEqual(decoded.sandboxBackend, .srt)
    }
}
