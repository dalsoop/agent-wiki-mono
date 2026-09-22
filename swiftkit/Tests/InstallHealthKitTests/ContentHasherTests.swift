import Foundation
import XCTest
@testable import InstallHealthKit

final class ContentHasherTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ContentHasherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    /// 동일한 소스 파일 구성 및 내용에 대해 항상 결정론적으로 동일한 해시가 생성되는지 검증
    func testDeterministicHashForIdenticalContent() throws {
        let sourcesDir = tempDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let fileA = sourcesDir.appendingPathComponent("A.swift")
        let fileB = sourcesDir.appendingPathComponent("B.swift")
        try "print(\"Hello\")".write(to: fileA, atomically: true, encoding: .utf8)
        try "print(\"World\")".write(to: fileB, atomically: true, encoding: .utf8)

        let hash1 = ContentHasher.computeHash(for: tempDir)
        let hash2 = ContentHasher.computeHash(for: tempDir)

        XCTAssertNotNil(hash1)
        XCTAssertEqual(hash1, hash2)
    }

    /// 파일 내용이 변경되었을 때 해시가 달라지는지 검증
    func testHashChangesWhenContentChanges() throws {
        let sourcesDir = tempDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let fileA = sourcesDir.appendingPathComponent("Main.swift")
        try "let x = 1".write(to: fileA, atomically: true, encoding: .utf8)

        let initialHash = ContentHasher.computeHash(for: tempDir)
        XCTAssertNotNil(initialHash)

        // 내용 수정
        try "let x = 2".write(to: fileA, atomically: true, encoding: .utf8)
        let modifiedHash = ContentHasher.computeHash(for: tempDir)

        XCTAssertNotNil(modifiedHash)
        XCTAssertNotEqual(initialHash, modifiedHash)
    }

    /// 새 소스 파일이 추가되었을 때 해시가 달라지는지 검증
    func testHashChangesWhenNewFileAdded() throws {
        let sourcesDir = tempDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let fileA = sourcesDir.appendingPathComponent("App.swift")
        try "struct App {}".write(to: fileA, atomically: true, encoding: .utf8)

        let initialHash = ContentHasher.computeHash(for: tempDir)
        XCTAssertNotNil(initialHash)

        let fileB = sourcesDir.appendingPathComponent("AppModel.swift")
        try "class AppModel {}".write(to: fileB, atomically: true, encoding: .utf8)

        let updatedHash = ContentHasher.computeHash(for: tempDir)
        XCTAssertNotNil(updatedHash)
        XCTAssertNotEqual(initialHash, updatedHash)
    }

    /// .git, .build 등 빌드 산출물/버전 관리 디렉터리는 해시 계산에서 제외되는지 검증
    func testExcludedDirectoriesAreIgnored() throws {
        let sourcesDir = tempDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let fileA = sourcesDir.appendingPathComponent("Core.swift")
        try "public struct Core {}".write(to: fileA, atomically: true, encoding: .utf8)

        let baseHash = ContentHasher.computeHash(for: tempDir)
        XCTAssertNotNil(baseHash)

        // .git 디렉터리 및 파일 생성
        let gitDir = tempDir.appendingPathComponent(".git", isDirectory: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/main".write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

        // .build 디렉터리 및 빌드 산출물 생성
        let buildDir = tempDir.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try "binary-object".write(to: buildDir.appendingPathComponent("debug.o"), atomically: true, encoding: .utf8)

        let hashWithBuildArtifacts = ContentHasher.computeHash(for: tempDir)
        XCTAssertEqual(baseHash, hashWithBuildArtifacts, ".git 및 .build 내 파일 추가는 소스 해시에 영향을 주지 않아야 합니다.")
    }

    /// Package.swift 및 package-identity.json 등 포함 대상 파일 인식 검증
    func testPackageAndIdentityFilesIncluded() throws {
        let packageSwift = tempDir.appendingPathComponent("Package.swift")
        try "// swift-tools-version: 6.0".write(to: packageSwift, atomically: true, encoding: .utf8)

        let hash1 = ContentHasher.computeHash(for: tempDir)
        XCTAssertNotNil(hash1)

        let identityPath = tempDir.appendingPathComponent("package-identity.json")
        try "{\"cli\":\"my-app\"}".write(to: identityPath, atomically: true, encoding: .utf8)

        let hash2 = ContentHasher.computeHash(for: tempDir)
        XCTAssertNotNil(hash2)
        XCTAssertNotEqual(hash1, hash2)
    }

    /// 비대상 확장자(.log, .tmp)는 무시되는지 검증
    func testNonSourceFilesAreIgnored() throws {
        let sourcesDir = tempDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let fileA = sourcesDir.appendingPathComponent("Util.swift")
        try "let u = 42".write(to: fileA, atomically: true, encoding: .utf8)

        let hashBefore = ContentHasher.computeHash(for: tempDir)

        let logFile = tempDir.appendingPathComponent("build.log")
        try "compilation finished".write(to: logFile, atomically: true, encoding: .utf8)

        let tmpFile = sourcesDir.appendingPathComponent("scratch.tmp")
        try "temporary data".write(to: tmpFile, atomically: true, encoding: .utf8)

        let hashAfter = ContentHasher.computeHash(for: tempDir)
        XCTAssertEqual(hashBefore, hashAfter, "비대상 확장자 파일(.log, .tmp)은 해시에 포함되지 않아야 합니다.")
    }

    /// 대상 소스 파일이 전혀 없는 디렉터리는 nil 반환 검증
    func testEmptyDirectoryReturnsNil() {
        let hash = ContentHasher.computeHash(for: tempDir)
        XCTAssertNil(hash, "대상 파일이 없는 빈 디렉터리는 nil 을 반환해야 합니다.")
    }

    /// 빈 Data의 SHA-256 표준 해시 값 검증
    func testEmptyDataSha256Hex() {
        let emptyData = Data()
        let expected = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        XCTAssertEqual(ContentHasher.sha256Hex(emptyData), expected)
    }
}
