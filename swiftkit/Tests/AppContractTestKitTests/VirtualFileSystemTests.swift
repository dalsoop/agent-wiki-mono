import XCTest
import AppContractTestKit

final class VirtualFileSystemTests: XCTestCase {
    var vfs = VirtualFileSystem()

    override func setUp() {
        super.setUp()
        vfs = VirtualFileSystem()
    }

    override func tearDown() {
        vfs.reset()
        super.tearDown()
    }

    func testBasicFileWriteAndRead() throws {
        let path = "/test/directory/sample.txt"
        let content = "Hermetic in-memory virtual file system test"

        try vfs.writeString(atPath: path, content: content, createIntermediateDirectories: true)

        XCTAssertTrue(vfs.fileExists(atPath: path))
        XCTAssertFalse(vfs.isDirectory(atPath: path))
        XCTAssertTrue(vfs.isDirectory(atPath: "/test/directory"))

        let readBack = try vfs.readString(atPath: path)
        XCTAssertEqual(readBack, content)
    }

    func testDirectoryCreationAndListing() throws {
        try vfs.createDirectory(atPath: "/a/b/c", withIntermediateDirectories: true)
        try vfs.writeString(atPath: "/a/b/c/file1.txt", content: "1")
        try vfs.writeString(atPath: "/a/b/c/file2.txt", content: "2")
        try vfs.createDirectory(atPath: "/a/b/c/sub", withIntermediateDirectories: false)

        let contents = try vfs.contentsOfDirectory(atPath: "/a/b/c")
        XCTAssertEqual(contents, ["file1.txt", "file2.txt", "sub"])

        let subpaths = try vfs.subpaths(atPath: "/a")
        XCTAssertEqual(subpaths, ["b", "b/c", "b/c/file1.txt", "b/c/file2.txt", "b/c/sub"])
    }

    func testRemoveItem() throws {
        try vfs.writeString(atPath: "/data/file.txt", content: "content", createIntermediateDirectories: true)
        XCTAssertTrue(vfs.fileExists(atPath: "/data/file.txt"))

        try vfs.removeItem(atPath: "/data/file.txt")
        XCTAssertFalse(vfs.fileExists(atPath: "/data/file.txt"))
        XCTAssertTrue(vfs.directoryExists(atPath: "/data"))

        try vfs.removeItem(atPath: "/data")
        XCTAssertFalse(vfs.directoryExists(atPath: "/data"))
    }

    func testCopyAndMove() throws {
        try vfs.writeString(atPath: "/source/item.txt", content: "payload", createIntermediateDirectories: true)
        try vfs.createDirectory(atPath: "/target", withIntermediateDirectories: true)

        try vfs.copyItem(atPath: "/source/item.txt", toPath: "/target/copied.txt")
        XCTAssertTrue(vfs.fileExists(atPath: "/source/item.txt"))
        XCTAssertTrue(vfs.fileExists(atPath: "/target/copied.txt"))
        XCTAssertEqual(try vfs.readString(atPath: "/target/copied.txt"), "payload")

        try vfs.moveItem(atPath: "/source/item.txt", toPath: "/target/moved.txt")
        XCTAssertFalse(vfs.fileExists(atPath: "/source/item.txt"))
        XCTAssertTrue(vfs.fileExists(atPath: "/target/moved.txt"))
        XCTAssertEqual(try vfs.readString(atPath: "/target/moved.txt"), "payload")
    }

    func testErrorHandling() throws {
        XCTAssertThrowsError(try vfs.readFile(atPath: "/nonexistent.txt")) { error in
            XCTAssertEqual(error as? VirtualFileSystemError, .fileNotFound("/nonexistent.txt"))
        }

        try vfs.createDirectory(atPath: "/existingDir", withIntermediateDirectories: true)
        XCTAssertThrowsError(try vfs.createDirectory(atPath: "/existingDir", withIntermediateDirectories: false)) { error in
            XCTAssertEqual(error as? VirtualFileSystemError, .alreadyExists("/existingDir"))
        }

        XCTAssertThrowsError(try vfs.removeItem(atPath: "/")) { error in
            XCTAssertEqual(error as? VirtualFileSystemError, .cannotRemoveRoot)
        }
    }
}

extension VirtualFileSystemProtocol {
    func directoryExists(atPath path: String) -> Bool {
        fileExists(atPath: path) && isDirectory(atPath: path)
    }
}
