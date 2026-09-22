import Compression
import Foundation

/// 디렉터리 트리를 zip 파일로 압축한다 — local file header / central directory / EOCD 를
/// 직접 쓰고, entry 데이터는 Apple `Compression`(COMPRESSION_ZLIB = raw DEFLATE)으로 압축한다.
/// 압축이 원본보다 커지거나 실패하면 STORE(method 0)로 폴백한다.
public enum ZipArchiveWriter {
    /// `directory` 아래 모든 파일·디렉터리를 `destinationURL` 에 zip 으로 쓴다.
    /// `directory` 자체는 root 로 취급되어 entry 이름에 포함되지 않는다.
    public static func write(
        directory: URL,
        to destinationURL: URL,
        excludingFileNames: Set<String> = [".DS_Store"],
        excludingDirectoryNames: Set<String> = ["__MACOSX"],
        fileManager: FileManager = .default
    ) throws {
        let rawEntries = try collectEntries(
            in: directory,
            excludingFileNames: excludingFileNames,
            excludingDirectoryNames: excludingDirectoryNames,
            fileManager: fileManager
        )

        var output = Data()
        var centralDirectory = Data()
        var recordCount: UInt16 = 0

        for raw in rawEntries {
            let localHeaderOffset = output.count
            let nameData = Data((raw.isDirectory ? raw.relativePath + "/" : raw.relativePath).utf8)
            let (dosTime, dosDate) = dosDateAndTime(from: raw.modificationDate)

            let uncompressed: Data = raw.isDirectory ? Data() : (try Data(contentsOf: raw.url))
            let crc = raw.isDirectory ? 0 : CRC32.checksum(uncompressed)

            let compressionMethod: UInt16
            let storedData: Data
            if raw.isDirectory || uncompressed.isEmpty {
                compressionMethod = 0
                storedData = uncompressed
            } else {
                var deflatedData: Data?
                do {
                    let res = try deflate(uncompressed)
                    if res.count < uncompressed.count {
                        deflatedData = res
                    }
                } catch {}
                if let deflated = deflatedData {
                    compressionMethod = 8
                    storedData = deflated
                } else {
                    compressionMethod = 0
                    storedData = uncompressed
                }
            }

            var local = Data()
            local.appendUInt32LE(ZipArchive.localFileHeaderSignature)
            local.appendUInt16LE(20) // version needed to extract
            local.appendUInt16LE(0) // general purpose bit flag
            local.appendUInt16LE(compressionMethod)
            local.appendUInt16LE(dosTime)
            local.appendUInt16LE(dosDate)
            local.appendUInt32LE(crc)
            local.appendUInt32LE(UInt32(storedData.count))
            local.appendUInt32LE(UInt32(uncompressed.count))
            local.appendUInt16LE(UInt16(nameData.count))
            local.appendUInt16LE(0) // extra field length
            local.append(nameData)
            output.append(local)
            output.append(storedData)

            var central = Data()
            central.appendUInt32LE(ZipArchive.centralDirectorySignature)
            central.appendUInt16LE(20) // version made by
            central.appendUInt16LE(20) // version needed to extract
            central.appendUInt16LE(0) // general purpose bit flag
            central.appendUInt16LE(compressionMethod)
            central.appendUInt16LE(dosTime)
            central.appendUInt16LE(dosDate)
            central.appendUInt32LE(crc)
            central.appendUInt32LE(UInt32(storedData.count))
            central.appendUInt32LE(UInt32(uncompressed.count))
            central.appendUInt16LE(UInt16(nameData.count))
            central.appendUInt16LE(0) // extra field length
            central.appendUInt16LE(0) // file comment length
            central.appendUInt16LE(0) // disk number start
            central.appendUInt16LE(0) // internal file attributes
            let externalAttrs: UInt32 = raw.isDirectory
                ? (UInt32(0o040755) << 16) | 0x10
                : (UInt32(0o100644) << 16)
            central.appendUInt32LE(externalAttrs)
            central.appendUInt32LE(UInt32(localHeaderOffset))
            central.append(nameData)
            centralDirectory.append(central)
            recordCount += 1
        }

        let centralDirectoryOffset = output.count
        output.append(centralDirectory)

        var eocd = Data()
        eocd.appendUInt32LE(ZipArchive.eocdSignature)
        eocd.appendUInt16LE(0) // number of this disk
        eocd.appendUInt16LE(0) // disk where central directory starts
        eocd.appendUInt16LE(recordCount)
        eocd.appendUInt16LE(recordCount)
        eocd.appendUInt32LE(UInt32(centralDirectory.count))
        eocd.appendUInt32LE(UInt32(centralDirectoryOffset))
        eocd.appendUInt16LE(0) // comment length
        output.append(eocd)

        do {
            try output.write(to: destinationURL, options: .atomic)
        } catch {
            throw ZipArchiveError.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - directory walk

    private struct RawEntry {
        let relativePath: String
        let isDirectory: Bool
        let modificationDate: Date
        let url: URL
    }

    private static func collectEntries(
        in directory: URL,
        excludingFileNames: Set<String>,
        excludingDirectoryNames: Set<String>,
        fileManager: FileManager
    ) throws -> [RawEntry] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: []
        ) else {
            throw ZipArchiveError.writeFailed("소스 디렉터리를 열 수 없음: \(directory.path)")
        }

        let basePath = directory.standardizedFileURL.path
        var rawEntries: [RawEntry] = []

        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = url.lastPathComponent

            if isDirectory, excludingDirectoryNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if !isDirectory, excludingFileNames.contains(name) {
                continue
            }

            let fullPath = url.standardizedFileURL.path
            guard fullPath.hasPrefix(basePath) else { continue }
            var relativePath = String(fullPath.dropFirst(basePath.count))
            if relativePath.hasPrefix("/") { relativePath.removeFirst() }
            guard !relativePath.isEmpty else { continue }

            let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? Date()
            rawEntries.append(
                RawEntry(relativePath: relativePath, isDirectory: isDirectory, modificationDate: modificationDate, url: url)
            )
        }

        rawEntries.sort { $0.relativePath < $1.relativePath }
        return rawEntries
    }

    // MARK: - compression

    private static func deflate(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + max(64, data.count / 2)
        var dst = Data(count: capacity)
        let encodedCount = dst.withUnsafeMutableBytes { dstRaw -> Int in
            data.withUnsafeBytes { srcRaw -> Int in
                guard let dstPtr = dstRaw.bindMemory(to: UInt8.self).baseAddress,
                      let srcPtr = srcRaw.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                // COMPRESSION_ZLIB 는 이름과 달리 zlib 헤더가 없는 raw DEFLATE 를 생성한다 —
                // 리더(ZipArchive.inflateRawDeflate)가 같은 알고리즘으로 디코드하는 바로 그 포맷.
                return compression_encode_buffer(dstPtr, capacity, srcPtr, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard encodedCount > 0 else { throw ZipArchiveError.compressionFailed }
        return dst.prefix(encodedCount)
    }

    // MARK: - DOS date/time

    private static func dosDateAndTime(from date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, comps.year ?? 1980)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = comps.second ?? 0

        let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
        let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        return (dosTime, dosDate)
    }
}
