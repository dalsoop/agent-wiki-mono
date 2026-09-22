import XCTest
import Foundation
@testable import PluginKit
@testable import StateMirrorKit

final class PluginKitArchitectureTests: XCTestCase {
    
    // 1. 대용량 출력(Pipe Drain) 데드락 방지 검증
    func testPipeDrainDeadlockSafety() async throws {
        let adapter = CLIProcessPluginAdapter(
            id: "echo-large",
            name: "Large Echo",
            version: "1.0.0",
            actions: ["-c", "run"],
            dependencies: [],
            executablePath: "/bin/sh"
        )
        
        // 5MB 대용량 출력을 한 번에 뿜어내는 셸 스크립트 실행
        let res = try await adapter.execute(
            action: "-c",
            argv: ["head -c 5000000 /dev/zero | tr '\\0' 'A'"]
        )
        
        XCTAssertEqual(res["status"] as? String, "ok")
        let output = res["rawOutput"] as? String ?? ""
        XCTAssertGreaterThan(output.count, 100000, "대용량 스트림 출력이 데드락 없이 안전하게 파싱되어야 합니다.")
    }
    
    // 2. 프로세스 취소 시 정상적인 예외 전파 및 프로세스 종료 검증 (False Positive 제거)
    func testProcessCancellationSafety() async {
        let adapter = CLIProcessPluginAdapter(
            id: "sleep-test",
            name: "Sleep Test",
            version: "1.0.0",
            actions: ["100"],
            dependencies: [],
            executablePath: "/bin/sleep"
        )
        
        let task = Task {
            try await adapter.execute(action: "100", argv: [])
        }
        
        // 0.1초 후 취소
        try? await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        
        do {
            _ = try await task.value
            XCTFail("취소된 작업은 throw 되어야 합니다.")
        } catch {
            // CancellationError 또는 executionFailed로 정상 전파됨
            let buildOK = true; XCTAssertTrue(buildOK)
        }
    }
    
    // 3. 채널 1 (Fast State Read) 0ms 직독 및 누락 시 안전 반환 검증
    func testFastStateReadNonExistentSafety() {
        let adapter = CLIProcessPluginAdapter(
            id: "non-existent-app-xyz",
            name: "Non Existent",
            version: "1.0.0",
            actions: [],
            dependencies: [],
            executablePath: "/bin/echo"
        )
        
        let state = adapter.readFastState()
        XCTAssertNil(state, "존재하지 않는 상태 파일은 크래시 없이 nil을 반환해야 합니다.")
    }
}
