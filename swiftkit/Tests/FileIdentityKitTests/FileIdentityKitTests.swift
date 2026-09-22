import XCTest
@testable import FileIdentityKit

final class FileIdentityKitTests: XCTestCase {
    func testWormIgnoresFileBytes() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("a.jpg")
        try Data("aaaa".utf8).write(to: url)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)

        let first = try FileStatReader.stat(url: url, relativeTo: dir)
        XCTAssertEqual(first.byteCount, 4)
        let id1 = FileIdentity.worm(first)

        try Data("bbbb".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        let second = try FileStatReader.stat(url: url, relativeTo: dir)
        XCTAssertEqual(second.byteCount, 4)
        XCTAssertEqual(FileIdentity.worm(second), id1)
    }

    func testWormChangesWhenSizeChanges() throws {
        let a = FileStat(relativePath: "x.jpg", byteCount: 10, modifiedAt: Date(timeIntervalSince1970: 1))
        let b = FileStat(relativePath: "x.jpg", byteCount: 11, modifiedAt: Date(timeIntervalSince1970: 1))
        XCTAssertNotEqual(FileIdentity.worm(a), FileIdentity.worm(b))
    }

    func testPathTokenStableUnderNFC() {
        let nfd = "갤럭시".decomposedStringWithCanonicalMapping
        let nfc = "갤럭시".precomposedStringWithCanonicalMapping
        XCTAssertEqual(FileIdentity.pathToken("a/\(nfd)"), FileIdentity.pathToken("a/\(nfc)"))
    }

    func testDirectoryFingerprintDoesNotNeedContent() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fid-dir-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("n.json")
        try Data("{}".utf8).write(to: file)
        let fp = DirectoryStatFingerprint.fingerprint(root: dir, fileExtension: "json")
        XCTAssertTrue(fp.hasPrefix("1:2:"), fp)
    }
}
