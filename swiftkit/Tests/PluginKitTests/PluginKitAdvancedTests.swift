import XCTest
@testable import PluginKit

final class PluginKitAdvancedTests: XCTestCase {
    
    // MARK: - 1. SemVer 2.0.0 정밀 비교 및 호환성 검증 테스트
    func testSemVerComparisonAndSatisfies() {
        let v100 = SemVer("1.0.0")
        let v120 = SemVer("1.2.0")
        let v121 = SemVer("1.2.1")
        let v200 = SemVer("2.0.0")
        let v100beta = SemVer("1.0.0-beta.1")
        
        // 순서 비교
        XCTAssertLessThan(v100beta, v100)
        XCTAssertLessThan(v100, v120)
        XCTAssertLessThan(v120, v121)
        XCTAssertLessThan(v121, v200)
        
        // satisfies 조건 검사
        XCTAssertTrue(v121.satisfies(minVersion: "1.2.0", maxVersion: "1.3.0"))
        XCTAssertTrue(v120.satisfies(minVersion: "1.2.0", maxVersion: "1.2.0")) // 경계값
        XCTAssertFalse(v100.satisfies(minVersion: "1.2.0")) // 미달
        XCTAssertFalse(v200.satisfies(maxVersion: "1.99.99")) // 초과
    }
    
    func testDependencyResolverVersionCompatibilityCheck() {
        let resolver = DependencyResolver()
        let installed: [String: SemVer] = [
            "agent-vault": SemVer("1.3.0"),
            "comfyui-studio": SemVer("2.1.0"),
            "old-tool": SemVer("0.9.0")
        ]
        
        // 정상 케이스
        let validReqs = [
            PluginDependencyRequirement(pluginId: "agent-vault", minVersion: "1.0.0", maxVersion: "1.5.0"),
            PluginDependencyRequirement(pluginId: "comfyui-studio", minVersion: "2.0.0")
        ]
        XCTAssertNoThrow(try resolver.validateVersionCompatibility(installedPlugins: installed, requirements: validReqs))
        
        // 구버전 미달 에러 케이스
        let outdatedReqs = [
            PluginDependencyRequirement(pluginId: "old-tool", minVersion: "1.0.0")
        ]
        XCTAssertThrowsError(try resolver.validateVersionCompatibility(installedPlugins: installed, requirements: outdatedReqs)) { error in
            guard case PluginError.executionFailed(let pluginId, let reason) = error else {
                XCTFail("예상치 못한 에러: \(error)")
                return
            }
            XCTAssertEqual(pluginId, "old-tool")
            XCTAssertTrue(reason.contains("버전 불일치"))
        }
        
        // 미설치 누락 에러 케이스
        let missingReqs = [
            PluginDependencyRequirement(pluginId: "missing-plugin", minVersion: "1.0.0")
        ]
        XCTAssertThrowsError(try resolver.validateVersionCompatibility(installedPlugins: installed, requirements: missingReqs)) { error in
            guard case PluginError.missingDependencies(let reason) = error else {
                XCTFail("예상치 못한 에러: \(error)")
                return
            }
            XCTAssertTrue(reason.contains("설치되어 있지 않습니다"))
        }
    }
    
    // MARK: - 2. 테넌트 환경변수 주입 검증
    func testPluginExecutionContextMakeEnvironment() {
        let context = PluginExecutionContext(tenantId: "tenant:marketing", roomId: "room-a")
        let env = context.makeEnvironment(inherited: ["EXISTING": "1"])
        
        XCTAssertEqual(env["TENANT_ID"], "tenant:marketing")
        XCTAssertEqual(env["ROOM_ID"], "room-a")
        XCTAssertEqual(env["EXISTING"], "1")
        // 페이블 잠금 헌법: 어댑터는 SWIFT_APP_STATE_ROOT 키를 임의로 생성/할당하지 않는다
        XCTAssertNil(env["SWIFT_APP_STATE_ROOT"])
    }
}
