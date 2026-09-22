import XCTest
@testable import WorktreeKit

final class APFSCoWHelperTests: XCTestCase {
    private var tempDir: URL = FileManager.default.temporaryDirectory

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create tempDir: \(error)")
        }
    }

    override func tearDown() {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testCloneItem_clonesFileAndMaintainsIsolation() throws {
        let srcFile = tempDir.appendingPathComponent("src.txt")
        let dstFile = tempDir.appendingPathComponent("dst.txt")
        try "initial content".write(to: srcFile, atomically: true, encoding: .utf8)

        try APFSCoWHelper.cloneItem(at: srcFile.path, to: dstFile.path)

        XCTAssertTrue(FileManager.default.fileExists(atPath: dstFile.path))
        XCTAssertEqual(try String(contentsOf: dstFile, encoding: .utf8), "initial content")

        // 대상 파일 수정 시 원본 파일에 영향을 주지 않는지(Copy-on-Write 격리) 확인
        try "modified content".write(to: dstFile, atomically: true, encoding: .utf8)
        XCTAssertEqual(try String(contentsOf: srcFile, encoding: .utf8), "initial content")
        XCTAssertEqual(try String(contentsOf: dstFile, encoding: .utf8), "modified content")
    }

    func testCloneDirectoryContents_excludesSpecifiedItems() throws {
        let srcDir = tempDir.appendingPathComponent("source")
        let dstDir = tempDir.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)

        try "package code".write(to: srcDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "readme".write(to: srcDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "git internal".write(to: srcDir.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        try APFSCoWHelper.cloneDirectoryContents(
            from: srcDir.path,
            to: dstDir.path,
            excluding: [".git"]
        )

        // 복제된 항목 검증
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstDir.appendingPathComponent("Package.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dstDir.appendingPathComponent("README.md").path))

        // 제외 대상(.git)은 복제되지 않아야 함
        XCTAssertFalse(FileManager.default.fileExists(atPath: dstDir.appendingPathComponent(".git").path))
    }
}
