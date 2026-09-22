import XCTest
@testable import RuleMiningKit

final class RecipeAutoPrescriberTests: XCTestCase {

    var prescriber: RecipeAutoPrescriber!

    override func setUp() {
        super.setUp()
        prescriber = RecipeAutoPrescriber()
    }

    override func tearDown() {
        prescriber = nil
        super.tearDown()
    }

    // MARK: - 1. AppPersistenceKit Transformation Unit Tests

    func testAppPersistenceTransformation() {
        let originalSource = """
        import Foundation

        public struct UserStore {
            public func loadUser(from data: Data) throws -> User {
                return try JSONDecoder().decode(User.self, from: data)
            }

            public func loadUserOptional(from data: Data) -> User? {
                return try? JSONDecoder().decode(User.self, from: data)
            }

            public func saveUser(_ user: User) throws -> Data {
                return try JSONEncoder().encode(user)
            }
        }
        """

        let (transformed, count, rules) = prescriber.applyTransformations(
            content: originalSource,
            transformations: RecipeAutoPrescriber.appPersistenceRecipe.transformations
        )

        XCTAssertEqual(count, 3)
        XCTAssertEqual(rules.count, 3)

        XCTAssertTrue(transformed.contains("try AppPersistence.decode(User.self, from: data)"))
        XCTAssertTrue(transformed.contains("try? AppPersistence.decode(User.self, from: data)"))
        XCTAssertTrue(transformed.contains("try AppPersistence.encode(user)"))
        XCTAssertFalse(transformed.contains("JSONDecoder().decode"))
        XCTAssertFalse(transformed.contains("JSONEncoder().encode"))

        // Import Injection
        let withImport = prescriber.injectImportStatement(
            content: transformed,
            moduleName: "AppPersistenceKit"
        )
        XCTAssertTrue(withImport.contains("import AppPersistenceKit"))
    }

    // MARK: - 2. ISO8601DateCodecKit Transformation Unit Tests

    func testISO8601DateCodecTransformation() {
        let originalSource = """
        import Foundation

        public struct LogEntry {
            public let timestamp = ISO8601DateFormatter().string(from: Date())

            public func format(custom date: Date) -> String {
                return ISO8601DateFormatter().string(from: date)
            }

            public func parse(raw text: String) -> Date? {
                return ISO8601DateFormatter().date(from: text)
            }
        }
        """

        let (transformed, count, rules) = prescriber.applyTransformations(
            content: originalSource,
            transformations: RecipeAutoPrescriber.iso8601DateCodecRecipe.transformations
        )

        XCTAssertEqual(count, 3)
        XCTAssertEqual(rules.count, 3)

        XCTAssertTrue(transformed.contains("let timestamp = DateCodec.isoNow()"))
        XCTAssertTrue(transformed.contains("DateCodec.formatISO8601(date)"))
        XCTAssertTrue(transformed.contains("DateCodec.parseISO8601(text)"))
        XCTAssertFalse(transformed.contains("ISO8601DateFormatter()"))

        // Import Injection
        let withImport = prescriber.injectImportStatement(
            content: transformed,
            moduleName: "ISO8601DateCodecKit"
        )
        XCTAssertTrue(withImport.contains("import ISO8601DateCodecKit"))
    }

    // MARK: - 3. Manifest Injection Unit Tests

    func testManifestInjection() {
        let samplePackageSwift = """
        // swift-tools-version: 6.1
        import PackageDescription

        let package = Package(
            name: "test-app",
            platforms: [.macOS(.v14)],
            products: [
                .executable(name: "test-app", targets: ["TestApp"])
            ],
            dependencies: [
                .package(path: "../../swiftkit"),
            ],
            targets: [
                .target(
                    name: "TestAppCore",
                    dependencies: [
                        .product(name: "FastDiskIOKit", package: "swiftkit"),
                    ]
                ),
                .executableTarget(
                    name: "TestApp",
                    dependencies: ["TestAppCore"]
                )
            ]
        )
        """

        let injected = prescriber.injectManifestDependency(
            pkgContent: samplePackageSwift,
            kitName: "AppPersistenceKit",
            targetNames: ["TestAppCore"]
        )

        XCTAssertTrue(injected.contains(".product(name: \"AppPersistenceKit\", package: \"swiftkit\")"))
        XCTAssertTrue(injected.contains("FastDiskIOKit"))

        // 중복 주입 방지 (Idempotency)
        let injectedTwice = prescriber.injectManifestDependency(
            pkgContent: injected,
            kitName: "AppPersistenceKit",
            targetNames: ["TestAppCore"]
        )
        XCTAssertEqual(injected, injectedTwice)
    }

    // MARK: - 4. Dry-Run & Actual Apply Integration Tests

    func testPrescribeDryRunAndApply() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AutoPrescriberTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Package.swift 작성
        let pkgContent = """
        // swift-tools-version: 6.1
        import PackageDescription

        let package = Package(
            name: "sample-agent",
            dependencies: [
                .package(path: "../../swiftkit"),
            ],
            targets: [
                .target(
                    name: "SampleAgentCore",
                    dependencies: []
                )
            ]
        )
        """
        try pkgContent.write(to: tempDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        // Sources/SampleAgentCore/Service.swift 작성
        let sourcesDir = tempDir.appendingPathComponent("Sources/SampleAgentCore", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        let serviceContent = """
        import Foundation

        public struct Service {
            public func parse(data: Data) throws -> String {
                return try JSONDecoder().decode(String.self, from: data)
            }
            public func stamp() -> String {
                return ISO8601DateFormatter().string(from: Date())
            }
        }
        """
        let fileURL = sourcesDir.appendingPathComponent("Service.swift")
        try serviceContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // 1. Dry Run 검증
        let dryResults = try prescriber.prescribe(
            appDirectory: tempDir,
            recipes: RecipeAutoPrescriber.standardRecipes,
            dryRun: true
        )

        XCTAssertEqual(dryResults.count, 2)
        XCTAssertTrue(dryResults[0].isDryRun)
        XCTAssertTrue(dryResults[0].manifestModified)
        XCTAssertEqual(dryResults[0].totalReplacements, 1) // JSONDecoder().decode

        XCTAssertTrue(dryResults[1].isDryRun)
        XCTAssertTrue(dryResults[1].manifestModified)
        XCTAssertEqual(dryResults[1].totalReplacements, 1) // ISO8601DateFormatter().string(from: Date())

        // Dry Run 이므로 원본 파일은 그대로 유지되어야 함
        let unchangedSource = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(unchangedSource, serviceContent)

        // 2. 실제 Apply 검증
        let applyResults = try prescriber.prescribe(
            appDirectory: tempDir,
            recipes: RecipeAutoPrescriber.standardRecipes,
            dryRun: false
        )

        XCTAssertEqual(applyResults.count, 2)
        XCTAssertFalse(applyResults[0].isDryRun)
        XCTAssertTrue(applyResults[0].success)

        // 소스 파일이 실제로 변환되었는지 검증
        let appliedSource = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(appliedSource.contains("import AppPersistenceKit"))
        XCTAssertTrue(appliedSource.contains("import ISO8601DateCodecKit"))
        XCTAssertTrue(appliedSource.contains("try AppPersistence.decode(String.self, from: data)"))
        XCTAssertTrue(appliedSource.contains("DateCodec.isoNow()"))
        XCTAssertFalse(appliedSource.contains("JSONDecoder().decode"))
        XCTAssertFalse(appliedSource.contains("ISO8601DateFormatter()"))

        // Package.swift가 실제로 수정되었는지 검증
        let appliedPkg = try String(contentsOf: tempDir.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(appliedPkg.contains(".product(name: \"AppPersistenceKit\", package: \"swiftkit\")"))
        XCTAssertTrue(appliedPkg.contains(".product(name: \"ISO8601DateCodecKit\", package: \"swiftkit\")"))
    }

    // MARK: - 5. Actual Fleet App Prescription Integration Test

    func testActualFleetAppPrescription() throws {
        // 모노레포 내의 실제 앱: apps/joint-certificate-manager-swift의 완전한 파일 구조를 복제하여
        // Dry-Run 및 실제 적용(Apply), Manifest Injection, 소스 변환을 격리 검증
        let currentFile = URL(fileURLWithPath: #file)
        let repoRoot = currentFile
            .deletingLastPathComponent() // RuleMiningKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // swiftkit
        let sourceAppDir = repoRoot.appendingPathComponent("apps/joint-certificate-manager-swift")

        guard FileManager.default.fileExists(atPath: sourceAppDir.path) else {
            XCTFail("Target app not found at \(sourceAppDir.path)")
            return
        }

        let tempAppDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FleetAppPrescriptionTest-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: sourceAppDir, to: tempAppDir)
        defer {
            try? FileManager.default.removeItem(at: tempAppDir)
        }

        // 1. Dry-Run 처방 검증
        let dryResult = try prescriber.prescribe(
            appDirectory: tempAppDir,
            recipe: RecipeAutoPrescriber.iso8601DateCodecRecipe,
            dryRun: true
        )

        XCTAssertTrue(dryResult.isDryRun)
        XCTAssertTrue(dryResult.success)

        // 2. 실제 처방(Apply) 적용
        let applyResult = try prescriber.prescribe(
            appDirectory: tempAppDir,
            recipe: RecipeAutoPrescriber.iso8601DateCodecRecipe,
            dryRun: false
        )

        XCTAssertFalse(applyResult.isDryRun)
        XCTAssertTrue(applyResult.success)

        // 3. 적용 결과 검증
        let pkgContent = try String(contentsOf: tempAppDir.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(pkgContent.contains(".product(name: \"ISO8601DateCodecKit\", package: \"swiftkit\")"))

        let publisherURL = tempAppDir.appendingPathComponent("Sources/JointCertificateManagerCore/CertificateHubPublisher.swift")
        let publisherContent = try String(contentsOf: publisherURL, encoding: .utf8)
        XCTAssertTrue(publisherContent.contains("import ISO8601DateCodecKit"))
        XCTAssertTrue(publisherContent.contains("DateCodec.isoNow()"))
        XCTAssertTrue(publisherContent.contains("DateCodec.formatISO8601(cert.validUntil)"))
        XCTAssertFalse(publisherContent.contains("ISO8601DateFormatter()"))
    }
}
