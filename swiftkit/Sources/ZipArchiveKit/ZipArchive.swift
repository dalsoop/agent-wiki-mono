import Compression
import Foundation

/// 의존성 0 ZIP 리더/라이터 — xlsx/hwpx/pptx 등 OOXML/개방형식 컨테이너(zip+XML)를 다루는
/// 여러 앱이 공유하는 순수 Swift 구현. 외부 프로세스(`/usr/bin/unzip`, `/usr/bin/zip`) 나
/// 원격 SPM 패키지에 의존하지 않는다 — Apple `Compression` 프레임워크로 raw DEFLATE 를
/// 직접 inflate/deflate 하고 zip 구조(local file header / central directory / EOCD)를 손으로 읽고 쓴다.
public enum ZipArchiveError: Error, Equatable, LocalizedError {
    case notAZipFile
    case endOfCentralDirectoryNotFound
    case corruptCentralDirectory
    case entryNotFound(String)
    case unsupportedCompressionMethod(UInt16)
    case decompressionFailed
    case compressionFailed
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAZipFile: return "zip 형식이 아님"
        case .endOfCentralDirectoryNotFound: return "zip end-of-central-directory 를 찾지 못함"
        case .corruptCentralDirectory: return "zip central directory 손상"
        case .entryNotFound(let name): return "zip entry 없음: \(name)"
        case .unsupportedCompressionMethod(let m): return "지원하지 않는 압축 방식: \(m)"
        case .decompressionFailed: return "압축 해제 실패"
        case .compressionFailed: return "압축 실패"
        case .writeFailed(let reason): return "zip 쓰기 실패: \(reason)"
        }
    }
}

/// 하나의 zip central-directory entry.
struct ZipEntry {
    let name: String
    let compressionMethod: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int
}

/// central directory 를 읽어 이름으로 entry 를 찾고, 필요할 때만 개별 압축 해제한다.
public struct ZipArchive {
    private let data: Data
    private let entries: [ZipEntry]
    private let indexByName: [String: Int]

    static let eocdSignature: UInt32 = 0x0605_4b50
    static let centralDirectorySignature: UInt32 = 0x0201_4b50
    static let localFileHeaderSignature: UInt32 = 0x0403_4b50

    public init(data: Data) throws {
        self.data = data
        let entries = try Self.parseCentralDirectory(data)
        self.entries = entries
        var index: [String: Int] = [:]
        index.reserveCapacity(entries.count)
        for (i, entry) in entries.enumerated() { index[entry.name] = i }
        self.indexByName = index
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url))
    }

    /// entry 존재 여부.
    public func contains(_ name: String) -> Bool { indexByName[name] != nil }

    /// central directory 에 등재된 모든 entry 이름(등록 순서 보존). 디렉터리 entry 는 "/" 로 끝난다.
    public var entryNames: [String] { entries.map(\.name) }

    /// entry 를 압축 해제한 바이트로 반환한다. 없으면 nil.
    public func dataIfPresent(_ name: String) throws -> Data? {
        guard let index = indexByName[name] else { return nil }
        return try extract(entries[index])
    }

    /// entry 를 압축 해제한 바이트로 반환한다. 없으면 throw.
    public func data(_ name: String) throws -> Data {
        guard let bytes = try dataIfPresent(name) else { throw ZipArchiveError.entryNotFound(name) }
        return bytes
    }

    /// 아카이브 전체를 `directory` 아래에 풀어 쓴다. 디렉터리 entry(이름이 "/"로 끝남)는
    /// 빈 디렉터리를 만들고, 그 외에는 상위 디렉터리를 만든 뒤 파일로 쓴다.
    public func extractAll(to directory: URL, fileManager: FileManager = .default) throws {
        for entry in entries {
            let destination = directory.appendingPathComponent(entry.name)
            if entry.name.hasSuffix("/") {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let bytes = try extract(entry)
            try bytes.write(to: destination, options: .atomic)
        }
    }

    // MARK: - central directory

    private static func parseCentralDirectory(_ data: Data) throws -> [ZipEntry] {
        guard data.count >= 22 else { throw ZipArchiveError.notAZipFile }

        // EOCD 는 comment(가변, 최대 65535B) 뒤에 있으니 파일 끝에서부터 서명을 역탐색한다.
        let searchFloor = max(0, data.count - 22 - 65_535)
        var eocdStart: Int?
        var offset = data.count - 22
        while offset >= searchFloor {
            if data.readUInt32LE(at: offset) == eocdSignature {
                eocdStart = offset
                break
            }
            offset -= 1
        }
        guard let eocd = eocdStart else { throw ZipArchiveError.endOfCentralDirectoryNotFound }

        let totalEntries = Int(data.readUInt16LE(at: eocd + 10))
        let centralDirectorySize = Int(data.readUInt32LE(at: eocd + 12))
        let centralDirectoryOffset = Int(data.readUInt32LE(at: eocd + 16))

        guard centralDirectoryOffset >= 0,
              centralDirectoryOffset + centralDirectorySize <= data.count
        else { throw ZipArchiveError.corruptCentralDirectory }

        var entries: [ZipEntry] = []
        entries.reserveCapacity(totalEntries)

        var cursor = centralDirectoryOffset
        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count,
                  data.readUInt32LE(at: cursor) == centralDirectorySignature
            else { throw ZipArchiveError.corruptCentralDirectory }

            let compressionMethod = data.readUInt16LE(at: cursor + 10)
            let compressedSize = Int(data.readUInt32LE(at: cursor + 20))
            let uncompressedSize = Int(data.readUInt32LE(at: cursor + 24))
            let nameLength = Int(data.readUInt16LE(at: cursor + 28))
            let extraLength = Int(data.readUInt16LE(at: cursor + 30))
            let commentLength = Int(data.readUInt16LE(at: cursor + 32))
            let localHeaderOffset = Int(data.readUInt32LE(at: cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { throw ZipArchiveError.corruptCentralDirectory }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? ""

            entries.append(
                ZipEntry(
                    name: name,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )

            cursor = nameStart + nameLength + extraLength + commentLength
        }

        return entries
    }

    // MARK: - entry extraction

    private func extract(_ entry: ZipEntry) throws -> Data {
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count,
              data.readUInt32LE(at: base) == Self.localFileHeaderSignature
        else { throw ZipArchiveError.corruptCentralDirectory }

        let nameLength = Int(data.readUInt16LE(at: base + 26))
        let extraLength = Int(data.readUInt16LE(at: base + 28))
        let dataStart = base + 30 + nameLength + extraLength
        guard dataStart + entry.compressedSize <= data.count else { throw ZipArchiveError.corruptCentralDirectory }

        let compressed = data.subdata(in: dataStart..<(dataStart + entry.compressedSize))

        switch entry.compressionMethod {
        case 0: // stored (no compression)
            return compressed
        case 8: // deflate
            return try Self.inflateRawDeflate(compressed, uncompressedSize: entry.uncompressedSize)
        default:
            throw ZipArchiveError.unsupportedCompressionMethod(entry.compressionMethod)
        }
    }

    private static func inflateRawDeflate(_ compressed: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        var output = Data(count: uncompressedSize)
        let decodedCount = output.withUnsafeMutableBytes { dstRaw -> Int in
            compressed.withUnsafeBytes { srcRaw -> Int in
                guard let dst = dstRaw.bindMemory(to: UInt8.self).baseAddress,
                      let src = srcRaw.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                // ZIP method 8 은 raw DEFLATE(zlib 헤더 없음) — Apple Compression 의 COMPRESSION_ZLIB
                // 알고리즘이 바로 이 raw deflate 스트림을 디코드한다.
                return compression_decode_buffer(
                    dst, uncompressedSize, src, compressed.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount == uncompressedSize else { throw ZipArchiveError.decompressionFailed }
        return output
    }
}

extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | (UInt16(self[startIndex + offset + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        UInt32(self[startIndex + offset])
            | (UInt32(self[startIndex + offset + 1]) << 8)
            | (UInt32(self[startIndex + offset + 2]) << 16)
            | (UInt32(self[startIndex + offset + 3]) << 24)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
