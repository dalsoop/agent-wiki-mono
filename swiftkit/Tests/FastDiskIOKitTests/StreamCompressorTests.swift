import XCTest
import Foundation
@testable import FastDiskIOKit

final class StreamCompressorTests: XCTestCase {
    private var tempDir: URL = FileManager.default.temporaryDirectory

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StreamCompressorTests_\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true) } catch { _ = error }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testDataRoundTripLZFSEAndLZ4() throws {
        var original = Data()
        for i in 0..<10_000 {
            original.append(contentsOf: "StreamCompressor-Test-Line-\(i)\n".utf8)
        }
        XCTAssertGreaterThan(original.count, 64 * 1024)

        // 1. LZFSE 압축 & 해제 라운드트립
        let compressedLZFSE = try StreamCompressor.compress(original, algorithm: .lzfse)
        XCTAssertLessThan(compressedLZFSE.count, original.count)
        let decompressedLZFSE = try StreamCompressor.decompress(compressedLZFSE, algorithm: .lzfse)
        XCTAssertEqual(decompressedLZFSE, original)

        // 2. LZ4 압축 & 해제 라운드트립
        let compressedLZ4 = try StreamCompressor.compress(original, algorithm: .lz4)
        XCTAssertLessThan(compressedLZ4.count, original.count)
        let decompressedLZ4 = try StreamCompressor.decompress(compressedLZ4, algorithm: .lz4)
        XCTAssertEqual(decompressedLZ4, original)

        // 3. ZLIB 압축 & 해제 라운드트립
        let compressedZLIB = try StreamCompressor.compress(original, algorithm: .zlib)
        XCTAssertLessThan(compressedZLIB.count, original.count)
        let decompressedZLIB = try StreamCompressor.decompress(compressedZLIB, algorithm: .zlib)
        XCTAssertEqual(decompressedZLIB, original)
    }

    func testFileHandleStreamRoundTrip() throws {
        let inputURL = tempDir.appendingPathComponent("input.bin")
        let compressedURL = tempDir.appendingPathComponent("compressed.bin")
        let outputURL = tempDir.appendingPathComponent("output.bin")

        var sourceData = Data(count: 128 * 1024)
        for i in 0..<sourceData.count {
            sourceData[i] = UInt8(i % 251)
        }
        try sourceData.write(to: inputURL)

        // Compress via FileHandle
        FileManager.default.createFile(atPath: compressedURL.path, contents: nil)
        let inHandle = try FileHandle(forReadingFrom: inputURL)
        let compOutHandle = try FileHandle(forWritingTo: compressedURL)
        try StreamCompressor.compress(stream: inHandle, to: compOutHandle, algorithm: .lzfse)
        try inHandle.close()
        try compOutHandle.close()

        // Decompress via FileHandle
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let compInHandle = try FileHandle(forReadingFrom: compressedURL)
        let outHandle = try FileHandle(forWritingTo: outputURL)
        try StreamCompressor.decompress(stream: compInHandle, to: outHandle, algorithm: .lzfse)
        try compInHandle.close()
        try outHandle.close()

        let recoveredData = try Data(contentsOf: outputURL)
        XCTAssertEqual(recoveredData, sourceData)
    }
}
