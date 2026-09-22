import XCTest
@testable import RuleMiningKit

final class HomeostaticClosedLoopOrchestratorTests: XCTestCase {

    var tempDir: URL!
    var mockAppDir: URL!
    var orchestrator: HomeostaticClosedLoopOrchestrator!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("orchestrator-tests-\(UUID().uuidString)")
        mockAppDir = tempDir.appendingPathComponent("mock-sample-app")
        do { try FileManager.default.createDirectory(at: mockAppDir, withIntermediateDirectories: true) } catch { _ = error }
        orchestrator = HomeostaticClosedLoopOrchestrator()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - 1. E2E 자율 치유 폐루프(Sensor ➔ Comparator ➔ Actuator ➔ Verifier) 테스트

    func testFullClosedLoopHealingCycle() async throws {
        // Step 0: 결손 상태의 Mock 앱 생성 (AppPersistenceKit 누락 + 원시 JSONDecoder/Encoder 보일러플레이트 보유)
        let packageSwiftContent = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "mock-sample-app",
            platforms: [.macOS(.v14)],
            dependencies: [
                .package(path: "../../swiftkit")
            ],
            targets: [
                .target(
                    name: "MockCore",
                    dependencies: []
                )
            ]
        )
        """
        try packageSwiftContent.write(
            to: mockAppDir.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let sourcesDir = mockAppDir.appendingPathComponent("Sources/MockCore")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let userStoreContent = """
        import Foundation

        public struct UserStore {
            public func loadUser(from data: Data) throws -> String {
                return try JSONDecoder().decode(String.self, from: data)
            }

            public func saveUser(_ value: String) throws -> Data {
                return try JSONEncoder().encode(value)
            }
        }
        """
        let userStoreURL = sourcesDir.appendingPathComponent("UserStore.swift")
        try userStoreContent.write(to: userStoreURL, atomically: true, encoding: .utf8)

        // Step 1: E2E 폐루프 실행 (Sensor ➔ Comparator ➔ Actuator ➔ Verifier)
        final class CallTracker: @unchecked Sendable {
            var called = false
        }
        let tracker = CallTracker()
        let result = try await orchestrator.runCycle(
            appDirectory: mockAppDir,
            dryRun: false,
            verifier: { url in
                tracker.called = true
                // 모의 TIA / 컴파일 검증 통과
                return true
            }
        )

        // Step 2: 판정 및 지표 검증
        XCTAssertTrue(tracker.called, "Verifier가 실제로 호출되어야 함")
        XCTAssertEqual(result.appSlug, "mock-sample-app")
        XCTAssertTrue(result.detectedGaps.contains(.appPersistenceKit), "AppPersistenceKit 결손이 감지되어야 함")
        XCTAssertEqual(result.detectedBoilerplateCount, 2, "2개의 원시 보일러플레이트가 적발되어야 함")
        XCTAssertTrue(result.appliedRecipeIDs.contains("recipe.app-persistence-kit"), "AppPersistence 처방이 적용되어야 함")
        XCTAssertGreaterThan(result.modifiedFilesCount, 0, "파일이 수정되어야 함")
        XCTAssertTrue(result.verifierSuccess, "검증이 성공해야 함")
        XCTAssertTrue(result.isHomeostasisRestored, "항상성이 자율 복원되어야 함")

        // Step 3: 디스크 파일 상태 검증 (Source AST Transformation + Manifest Injection)
        let modifiedSource = try String(contentsOf: userStoreURL, encoding: .utf8)
        XCTAssertTrue(modifiedSource.contains("import AppPersistenceKit"), "import 문이 주입되어야 함")
        XCTAssertTrue(modifiedSource.contains("try AppPersistence.decode(String.self, from: data)"), "고수준 API로 치환되어야 함")
        XCTAssertTrue(modifiedSource.contains("try AppPersistence.encode(value)"), "고수준 API로 치환되어야 함")
        XCTAssertFalse(modifiedSource.contains("JSONDecoder().decode"), "원시 보일러플레이트가 제거되어야 함")

        let modifiedPkg = try String(contentsOf: mockAppDir.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(modifiedPkg.contains(".product(name: \"AppPersistenceKit\", package: \"swiftkit\")"), "매니페스트에 의존성이 주입되어야 함")
    }

    // MARK: - 2. Dry-Run 안전 시뮬레이션 테스트

    func testDryRunSimulationLeavesDiskIntact() async throws {
        let packageSwiftContent = """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(name: "mock-app", dependencies: [], targets: [.target(name: "MockCore")])
        """
        let pkgURL = mockAppDir.appendingPathComponent("Package.swift")
        try packageSwiftContent.write(to: pkgURL, atomically: true, encoding: .utf8)

        let sourcesDir = mockAppDir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let sourceFile = sourcesDir.appendingPathComponent("Test.swift")
        let sourceContent = "import Foundation\nlet x = try JSONDecoder().decode(Int.self, from: data)"
        try sourceContent.write(to: sourceFile, atomically: true, encoding: .utf8)

        let result = try await orchestrator.runCycle(
            appDirectory: mockAppDir,
            dryRun: true
        )

        XCTAssertTrue(result.detectedGaps.contains(.appPersistenceKit))
        XCTAssertFalse(result.isHomeostasisRestored, "Dry run에서는 파일이 변경되지 않으므로 복원 완료가 아니어야 함")

        // 원본 파일 보존 확인
        let currentSource = try String(contentsOf: sourceFile, encoding: .utf8)
        XCTAssertEqual(currentSource, sourceContent, "Dry-run 모드에서는 소스 파일이 수정되면 안 됨")
    }

    // MARK: - 3. 이미 정상인 앱에 대한 No-Op 테스트

    func testAlreadyHealthyAppIsNoOp() async throws {
        let packageSwiftContent = """
        // swift-tools-version: 5.9
        import PackageDescription
        let package = Package(
            name: "healthy-app",
            dependencies: [
                .product(name: "AppPersistenceKit", package: "swiftkit"),
                .product(name: "AppWindowKit", package: "swiftkit"),
                .product(name: "ISO8601DateCodecKit", package: "swiftkit"),
                .product(name: "SettingsUIKit", package: "swiftkit"),
                .product(name: "OnboardingUIKit", package: "swiftkit"),
                .product(name: "PackageIdentityKit", package: "swiftkit")
            ],
            targets: [.target(name: "Core")]
        )
        """
        try packageSwiftContent.write(to: mockAppDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let sourcesDir = mockAppDir.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let cleanSource = "import Foundation\npublic struct Clean {}"
        try cleanSource.write(to: sourcesDir.appendingPathComponent("Clean.swift"), atomically: true, encoding: .utf8)

        let result = try await orchestrator.runCycle(appDirectory: mockAppDir, dryRun: false)

        XCTAssertTrue(result.detectedGaps.isEmpty)
        XCTAssertTrue(result.isHomeostasisRestored)
        XCTAssertEqual(result.appliedRecipeIDs.count, 0)
    }
}
