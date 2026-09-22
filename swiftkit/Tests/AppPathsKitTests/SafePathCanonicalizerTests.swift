import XCTest
@testable import AppPathsKit

final class SafePathCanonicalizerTests: XCTestCase {

    private var tempBoundary: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent("SafePathTest-\(UUID().uuidString)")
        try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
        tempBoundary = try SafePathCanonicalizer.canonicalPath(for: baseDir)
    }

    override func tearDownWithError() throws {
        if let tempBoundary = tempBoundary {
            try? FileManager.default.removeItem(at: tempBoundary)
        }
        try super.tearDownWithError()
    }

    private func requireBoundary() throws -> URL {
        guard let tempBoundary = tempBoundary else {
            throw XCTSkip("Boundary not initialized")
        }
        return tempBoundary
    }

    func testResolveNormalRelativePath() throws {
        let boundary = try requireBoundary()
        let subDir = boundary.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let sampleFile = subDir.appendingPathComponent("main.swift")
        try "print(\"hello\")".write(to: sampleFile, atomically: true, encoding: .utf8)

        let resolved = try SafePathCanonicalizer.resolveWithin(boundary: boundary, path: "Sources/App/main.swift")
        XCTAssertEqual(resolved.path, sampleFile.path)
    }

    func testRejectDirectoryTraversal() throws {
        let boundary = try requireBoundary()
        XCTAssertThrowsError(
            try SafePathCanonicalizer.resolveWithin(boundary: boundary, path: "../../etc/passwd")
        ) { error in
            guard let safeError = error as? SafePathError else {
                XCTFail("Unexpected error type: \(error)")
                return
            }
            switch safeError {
            case .traversalDetected, .outsideBoundary:
                // Expected protection
                break
            default:
                XCTFail("Expected traversal or outside boundary error, got: \(safeError)")
            }
        }
    }

    func testRejectSymlinkEscape() throws {
        let fm = FileManager.default
        // 외부 민감 디렉터리 모의 (외부 임시 폴더)
        let outsideDir = fm.temporaryDirectory.appendingPathComponent("OutsideSecret-\(UUID().uuidString)")
        try fm.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outsideDir) }

        let secretFile = outsideDir.appendingPathComponent("secret.txt")
        try "CONFIDENTIAL".write(to: secretFile, atomically: true, encoding: .utf8)

        let boundary = try requireBoundary()
        // boundary 내부에 외부를 가리키는 악의적 심볼릭 링크 생성
        let symlinkPath = boundary.appendingPathComponent("malicious_symlink")
        try fm.createSymbolicLink(at: symlinkPath, withDestinationURL: outsideDir)

        // 심볼릭 링크를 타고 들어가 외부 파일을 읽으려는 시도 차단 검증
        XCTAssertThrowsError(
            try SafePathCanonicalizer.resolveWithin(boundary: boundary, path: "malicious_symlink/secret.txt")
        ) { error in
            guard let safeError = error as? SafePathError else {
                XCTFail("Unexpected error type: \(error)")
                return
            }
            guard case .outsideBoundary = safeError else {
                XCTFail("Expected outsideBoundary error, got: \(safeError)")
                return
            }
        }
    }

    func testPermitInternalSymlink() throws {
        let boundary = try requireBoundary()
        let fm = FileManager.default
        let internalRealDir = boundary.appendingPathComponent("RealDir")
        try fm.createDirectory(at: internalRealDir, withIntermediateDirectories: true)

        let internalLink = boundary.appendingPathComponent("LinkToReal")
        try fm.createSymbolicLink(at: internalLink, withDestinationURL: internalRealDir)

        let targetFile = internalRealDir.appendingPathComponent("data.json")
        try "{}".write(to: targetFile, atomically: true, encoding: .utf8)

        let resolved = try SafePathCanonicalizer.resolveWithin(boundary: boundary, path: "LinkToReal/data.json")
        XCTAssertEqual(resolved.path, targetFile.path)
    }

    func testNonExistentNewFileWithinBoundary() throws {
        let boundary = try requireBoundary()
        let newFilePath = "Drafts/Subfolder/new_file.txt"
        let resolved = try SafePathCanonicalizer.resolveWithin(boundary: boundary, path: newFilePath)
        XCTAssertTrue(resolved.path.hasPrefix(boundary.path))
        XCTAssertTrue(resolved.path.hasSuffix("new_file.txt"))
    }

    func testNonExistentNewFileEscapingBoundary() throws {
        let boundary = try requireBoundary()
        XCTAssertThrowsError(
            try SafePathCanonicalizer.resolveWithin(boundary: boundary, path: "Sub/../../outside_new.txt")
        ) { error in
            XCTAssertNotNil(error as? SafePathError)
        }
    }
}
