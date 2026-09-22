import XCTest
@testable import RuleMiningKit

final class CodebaseRepoMapIndexerTests: XCTestCase {

    var indexer: CodebaseRepoMapIndexer!

    override func setUp() {
        super.setUp()
        indexer = CodebaseRepoMapIndexer()
    }

    // MARK: - 1. 단일 소스 AST 정밀 인덱싱 테스트

    func testSingleSourceIndexing() {
        let sourceCode = """
        import Foundation
        import SwiftUI

        // 사용자 프로필 모델 (주석 무시 테스트)
        public struct UserProfile: Identifiable, Codable {
            public let id: UUID
            public var name: String
            private var internalToken: String = "secret-token"

            public init(id: UUID = UUID(), name: String) {
                self.id = id
                self.name = name
            }

            public func displayName() -> String {
                return name
            }

            /*
             다중행 블록 주석
             func fakeMethod() { ... }
             */
            private func cleanSecrets() {
                // 내부 정리 로직
            }
        }

        public enum UserRole: String, CaseIterable {
            case admin
            case member
            case guest
        }

        public protocol TaskExecutor {
            var isRunning: Bool { get }
            func execute(jobId: String) async throws -> Bool
        }
        """

        let fileMap = indexer.indexSource(code: sourceCode, relativePath: "Sources/Models/UserProfile.swift")

        // 1. import 검증
        XCTAssertEqual(fileMap.imports, ["Foundation", "SwiftUI"])

        // 2. 타입 선언 검증 (UserProfile, UserRole, TaskExecutor)
        XCTAssertEqual(fileMap.types.count, 3)

        let userProfile = fileMap.types[0]
        XCTAssertEqual(userProfile.kind, .struct)
        XCTAssertEqual(userProfile.name, "UserProfile")
        XCTAssertEqual(userProfile.accessLevel, .public)
        XCTAssertEqual(userProfile.conformances, ["Identifiable", "Codable"])

        // 프로퍼티 검증
        XCTAssertEqual(userProfile.properties.count, 3)
        let idProp = userProfile.properties[0]
        XCTAssertEqual(idProp.name, "id")
        XCTAssertEqual(idProp.accessLevel, .public)
        XCTAssertTrue(idProp.isConstant)

        // 메서드 검증 (init, displayName, cleanSecrets)
        XCTAssertEqual(userProfile.functions.count, 3)
        let displayFn = userProfile.functions.first { $0.name == "displayName" }
        XCTAssertNotNil(displayFn)
        XCTAssertEqual(displayFn?.accessLevel, .public)
        XCTAssertEqual(displayFn?.returnType, "String")

        // 3. Enum 검증
        let userRole = fileMap.types[1]
        XCTAssertEqual(userRole.kind, .enum)
        XCTAssertEqual(userRole.name, "UserRole")
        XCTAssertEqual(userRole.cases.count, 3)
        XCTAssertEqual(userRole.cases, ["admin", "member", "guest"])

        // 4. Protocol 검증
        let executor = fileMap.types[2]
        XCTAssertEqual(executor.kind, .protocol)
        XCTAssertEqual(executor.name, "TaskExecutor")
        XCTAssertEqual(executor.functions.count, 1)

        let execFn = executor.functions[0]
        XCTAssertEqual(execFn.name, "execute")
        XCTAssertTrue(execFn.isAsync)
        XCTAssertTrue(execFn.isThrows)
        XCTAssertEqual(execFn.returnType, "Bool")
    }

    // MARK: - 2. 중첩 타입 및 복합 시그니처 인덱싱 테스트

    func testNestedTypesAndComplexSignatures() {
        let sourceCode = """
        import Combine

        public final class EngineManager: ObservableObject {
            public struct Configuration {
                public var timeoutSeconds: Int
                public var retryLimit: Int
            }

            @Published public private(set) var state: String = "idle"
            public static let shared: EngineManager = EngineManager()

            @MainActor
            public func start(with config: Configuration) async throws -> Void {
                // start engine
            }

            public mutating func reset() {
                // mutating test
            }
        }
        """

        let fileMap = indexer.indexSource(code: sourceCode, relativePath: "Sources/Core/EngineManager.swift")

        XCTAssertEqual(fileMap.types.count, 1)
        let engine = fileMap.types[0]
        XCTAssertEqual(engine.kind, .class)
        XCTAssertEqual(engine.name, "EngineManager")
        XCTAssertEqual(engine.accessLevel, .public)

        // 중첩 타입 검증
        XCTAssertEqual(engine.nestedTypes.count, 1)
        let config = engine.nestedTypes[0]
        XCTAssertEqual(config.name, "Configuration")
        XCTAssertEqual(config.kind, .struct)
        XCTAssertEqual(config.properties.count, 2)

        // static 프로퍼티 검증
        let sharedProp = engine.properties.first { $0.name == "shared" }
        XCTAssertNotNil(sharedProp)
        XCTAssertTrue(sharedProp?.isStatic ?? false)

        // 메서드 속성 및 비동기 검증
        let startFn = engine.functions.first { $0.name == "start" }
        XCTAssertNotNil(startFn)
        XCTAssertTrue(startFn?.isAsync ?? false)
        XCTAssertTrue(startFn?.isThrows ?? false)
    }

    // MARK: - 3. Package.swift 파싱 테스트

    func testPackageSwiftParsing() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do { try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true) } catch { _ = error }
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageSwiftContent = """
        // swift-tools-version: 6.1
        import PackageDescription

        let package = Package(
            name: "agent-sample-swift",
            platforms: [.macOS(.v15)],
            products: [
                .executable(name: "agent-sample", targets: ["AgentSampleCLI"]),
                .library(name: "AgentSampleCore", targets: ["AgentSampleCore"]),
            ],
            dependencies: [
                .package(path: "../../swiftkit"),
            ],
            targets: [
                .target(
                    name: "AgentSampleCore",
                    dependencies: [
                        .product(name: "StateRootKit", package: "swiftkit"),
                        .product(name: "WorkflowPipelineKit", package: "swiftkit"),
                    ]
                ),
                .executableTarget(
                    name: "AgentSampleCLI",
                    dependencies: ["AgentSampleCore"]
                ),
                .testTarget(
                    name: "AgentSampleTests",
                    dependencies: ["AgentSampleCore"]
                )
            ]
        )
        """

        let packageURL = tempDir.appendingPathComponent("Package.swift")
        try! packageSwiftContent.write(to: packageURL, atomically: true, encoding: .utf8)

        let summary = indexer.parsePackageSwift(at: packageURL)
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.name, "agent-sample-swift")
        XCTAssertEqual(summary?.products, ["agent-sample", "AgentSampleCore"])
        XCTAssertTrue(summary?.kitDependencies.contains("StateRootKit") ?? false)
        XCTAssertTrue(summary?.kitDependencies.contains("WorkflowPipelineKit") ?? false)
        XCTAssertEqual(summary?.targets.count, 3)
    }

    // MARK: - 4. 토큰 예산 피팅 및 ACI 프롬프트 포매팅 테스트

    func testTokenBudgetAndCompacting() {
        var files: [FileRepoMap] = []
        // 대량의 타입 및 메서드를 생성하여 토큰 예산 초과 상황 시뮬레이션
        for i in 1...20 {
            let types = (1...5).map { tIndex in
                TypeDeclarationMap(
                    kind: .struct,
                    name: "ServiceType_\(i)_\(tIndex)",
                    conformances: ["Sendable", "Codable"],
                    accessLevel: .public,
                    properties: (1...5).map { p in
                        PropertySignatureMap(name: "property_\(p)", type: "String", accessLevel: .public)
                    },
                    functions: (1...5).map { m in
                        FunctionSignatureMap(
                            name: "method_\(m)",
                            signature: "func method_\(m)(arg: String) async throws -> Int",
                            returnType: "Int",
                            accessLevel: .public,
                            isAsync: true,
                            isThrows: true
                        )
                    }
                )
            }
            files.append(FileRepoMap(path: "Sources/Module\(i)/File\(i).swift", types: types))
        }

        let options = RepoMapOptions(maxTokenBudget: 500, detailLevel: .full)
        let formatted = indexer.formatRepoMap(
            appSlug: "big-app-swift",
            packageSummary: PackageSummary(name: "big-app-swift", products: ["big-app"]),
            files: files,
            options: options
        )

        let tokens = CodebaseRepoMapIndexer.estimateTokenCount(formatted)
        XCTAssertLessThanOrEqual(tokens, 500, "500 토큰 예산 제약을 초과하지 않아야 함 (실측: \(tokens) tokens)")

        let summary = RepoMapSummary(
            appSlug: "big-app-swift",
            rootPath: "/path/to/big-app",
            files: files,
            totalFiles: files.count,
            totalTypes: 100,
            totalFunctions: 500,
            estimatedTokens: tokens,
            formattedMap: formatted
        )

        // ACI 컨텍스트 블록 출력 검증
        let aciPrompt = summary.asAgentContextPrompt()
        XCTAssertTrue(aciPrompt.contains("### Codebase Repository Map (big-app-swift)"))
        XCTAssertTrue(aciPrompt.contains("Files: 20"))
        XCTAssertTrue(aciPrompt.contains("```swift"))

        // JSON 직렬화 검증
        let json = summary.toJSONString()
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains("big-app-swift") ?? false)
    }

    // MARK: - 5. 실제 모노레포 앱(`apps/agent-chat-swift`) 실전 인덱싱 검증

    func testLiveAppIndexing() throws {
        let repoRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // RuleMiningKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // swiftkit
            .deletingLastPathComponent() // main

        let appURL = repoRoot.appendingPathComponent("apps/agent-chat-swift")
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            // CI 환경 등 경로가 다를 경우 스킵
            return
        }

        let options = RepoMapOptions(maxTokenBudget: 2000, detailLevel: .standard)
        let summary = try indexer.indexApp(at: appURL, options: options)

        XCTAssertEqual(summary.appSlug, "agent-chat-swift")
        XCTAssertGreaterThan(summary.totalFiles, 0, "최소 1개 이상의 소스 파일이 인덱싱되어야 함")
        XCTAssertGreaterThan(summary.totalTypes, 0, "핵심 타입이 추출되어야 함")
        XCTAssertGreaterThan(summary.totalFunctions, 0, "메서드 시그니처가 추출되어야 함")
        XCTAssertLessThanOrEqual(summary.estimatedTokens, 2000, "2,000 토큰 예산 내에 맞춰져야 함 (실측: \(summary.estimatedTokens) tokens)")

        XCTAssertNotNil(summary.packageSummary)
        XCTAssertFalse(summary.formattedMap.isEmpty)
    }
}
