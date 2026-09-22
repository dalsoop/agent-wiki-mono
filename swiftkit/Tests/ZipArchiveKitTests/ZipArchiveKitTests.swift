import XCTest
@testable import ZipArchiveKit

final class ZipArchiveKitTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-archive-kit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ content: Data, relativePath: String, in root: URL) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url)
    }

    // MARK: - round trip

    func testWriteThenReadRoundTripsFileContents() throws {
        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        try write(Data("hello world".utf8), relativePath: "a.txt", in: sourceDir)
        try write(Data("nested content".utf8), relativePath: "nested/b.txt", in: sourceDir)

        let zipURL = tempDir.appendingPathComponent("out.zip")
        try ZipArchiveWriter.write(directory: sourceDir, to: zipURL)

        let archive = try ZipArchive(contentsOf: zipURL)
        XCTAssertTrue(archive.contains("a.txt"))
        XCTAssertTrue(archive.contains("nested/b.txt"))
        XCTAssertEqual(try archive.data("a.txt"), Data("hello world".utf8))
        XCTAssertEqual(try archive.data("nested/b.txt"), Data("nested content".utf8))
    }

    func testExtractAllReproducesDirectoryTree() throws {
        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        try write(Data("root file".utf8), relativePath: "root.txt", in: sourceDir)
        try write(Data("deep file".utf8), relativePath: "a/b/c.txt", in: sourceDir)

        let zipURL = tempDir.appendingPathComponent("out.zip")
        try ZipArchiveWriter.write(directory: sourceDir, to: zipURL)

        let extractDir = tempDir.appendingPathComponent("extracted", isDirectory: true)
        let archive = try ZipArchive(contentsOf: zipURL)
        try archive.extractAll(to: extractDir)

        XCTAssertEqual(
            try Data(contentsOf: extractDir.appendingPathComponent("root.txt")),
            Data("root file".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: extractDir.appendingPathComponent("a/b/c.txt")),
            Data("deep file".utf8)
        )
    }

    // MARK: - empty file

    func testEmptyFileRoundTrips() throws {
        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        try write(Data(), relativePath: "empty.txt", in: sourceDir)

        let zipURL = tempDir.appendingPathComponent("out.zip")
        try ZipArchiveWriter.write(directory: sourceDir, to: zipURL)

        let archive = try ZipArchive(contentsOf: zipURL)
        XCTAssertEqual(try archive.data("empty.txt"), Data())
    }

    // MARK: - directory entries

    func testEmptyDirectoryProducesDirectoryEntry() throws {
        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        let emptySubdir = sourceDir.appendingPathComponent("empty-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: emptySubdir, withIntermediateDirectories: true)

        let zipURL = tempDir.appendingPathComponent("out.zip")
        try ZipArchiveWriter.write(directory: sourceDir, to: zipURL)

        let archive = try ZipArchive(contentsOf: zipURL)
        XCTAssertTrue(archive.entryNames.contains("empty-dir/"))
    }

    func testDSStoreAndMacOSXAreExcluded() throws {
        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        try write(Data("keep".utf8), relativePath: "keep.txt", in: sourceDir)
        try write(Data("junk".utf8), relativePath: ".DS_Store", in: sourceDir)
        try write(Data("junk".utf8), relativePath: "__MACOSX/keep.txt", in: sourceDir)

        let zipURL = tempDir.appendingPathComponent("out.zip")
        try ZipArchiveWriter.write(directory: sourceDir, to: zipURL)

        let archive = try ZipArchive(contentsOf: zipURL)
        XCTAssertTrue(archive.contains("keep.txt"))
        XCTAssertFalse(archive.entryNames.contains { $0.contains(".DS_Store") })
        XCTAssertFalse(archive.entryNames.contains { $0.contains("__MACOSX") })
    }

    // MARK: - large file (forces deflate to actually engage, not just STORE fallback)

    func testLargeCompressibleFileRoundTrips() throws {
        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        let repeatedLine = "the quick brown fox jumps over the lazy dog\n"
        let big = String(repeating: repeatedLine, count: 20_000)
        try write(Data(big.utf8), relativePath: "big.txt", in: sourceDir)

        let zipURL = tempDir.appendingPathComponent("out.zip")
        try ZipArchiveWriter.write(directory: sourceDir, to: zipURL)

        let zipSize = try Data(contentsOf: zipURL).count
        XCTAssertLessThan(zipSize, big.utf8.count, "highly repetitive content should compress smaller than source")

        let archive = try ZipArchive(contentsOf: zipURL)
        XCTAssertEqual(try archive.data("big.txt"), Data(big.utf8))
    }

    func testLargeRandomFileRoundTrips() throws {
        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        var generator = SystemRandomNumberGenerator()
        var bytes = [UInt8]()
        bytes.reserveCapacity(500_000)
        for _ in 0..<500_000 { bytes.append(UInt8.random(in: 0...255, using: &generator)) }
        let randomData = Data(bytes)
        try write(randomData, relativePath: "random.bin", in: sourceDir)

        let zipURL = tempDir.appendingPathComponent("out.zip")
        try ZipArchiveWriter.write(directory: sourceDir, to: zipURL)

        let archive = try ZipArchive(contentsOf: zipURL)
        XCTAssertEqual(try archive.data("random.bin"), randomData)
    }

    // MARK: - invalid input

    func testGarbageDataIsRejected() {
        let garbage = Data("this is not a zip file at all".utf8)
        XCTAssertThrowsError(try ZipArchive(data: garbage)) { error in
            XCTAssertEqual(error as? ZipArchiveError, .endOfCentralDirectoryNotFound)
        }
    }

    func testTooShortDataIsRejected() {
        XCTAssertThrowsError(try ZipArchive(data: Data([0x50, 0x4B]))) { error in
            XCTAssertEqual(error as? ZipArchiveError, .notAZipFile)
        }
    }

    func testMissingEntryThrows() throws {
        let sourceDir = tempDir.appendingPathComponent("source", isDirectory: true)
        try write(Data("x".utf8), relativePath: "a.txt", in: sourceDir)
        let zipURL = tempDir.appendingPathComponent("out.zip")
        try ZipArchiveWriter.write(directory: sourceDir, to: zipURL)

        let archive = try ZipArchive(contentsOf: zipURL)
        XCTAssertThrowsError(try archive.data("missing.txt")) { error in
            XCTAssertEqual(error as? ZipArchiveError, .entryNotFound("missing.txt"))
        }
        XCTAssertNil(try archive.dataIfPresent("missing.txt"))
    }
}
