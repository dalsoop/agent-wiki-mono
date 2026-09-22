import Foundation

/// 이미지 메타데이터 (Pure Swift, OS 비종속)
public struct ImageHeaderMetadata: Sendable, Codable {
    public let width: Int
    public let height: Int
    public let format: String
    public let byteSize: Int64

    public init(width: Int, height: Int, format: String, byteSize: Int64) {
        self.width = width
        self.height = height
        self.format = format
        self.byteSize = byteSize
    }
}

/// 64KB 스트리밍 I/O 및 Big-Endian 정규화 파서 (OOM 및 엔디안 결함 원천 차단)
public enum SafeBinaryReader {
    public static func inspectImage(fileURL: URL) throws -> ImageHeaderMetadata {
        let fileManager = FileManager.default
        let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
        let totalSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            do {
                try handle.close()
            } catch {
                _ = error
            }
        }

        // 전체 파일을 메모리에 적재하지 않고 앞부분 64KB만 청크로 읽음 (OOM 방지)
        guard let chunk = try handle.read(upToCount: 65536), chunk.count >= 16 else {
            throw BinaryParseError.insufficientData
        }

        let ext = fileURL.pathExtension.lowercased()

        // 1. SVG 벡터 포맷 처리
        if ext == "svg" {
            return try parseSVG(fileURL: fileURL, totalSize: totalSize)
        }

        // 2. 바이너리 포맷 처리

        if ext == "png" || isPNG(chunk) {
            return try parsePNG(chunk, totalSize: totalSize)
        } else if ext == "jpg" || ext == "jpeg" || isJPEG(chunk) {
            return try parseJPEG(chunk, handle: handle, totalSize: totalSize)
        } else if ext == "pdf" {
            return try parsePDF(fileURL: fileURL, handle: handle, totalSize: totalSize)
        }

        // 지원 포맷 외 기본 fallback
        return ImageHeaderMetadata(width: 0, height: 0, format: ext.uppercased(), byteSize: totalSize)
    }

    private static func isPNG(_ data: Data) -> Bool {
        guard data.count >= 8 else { return false }
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return data.prefix(8).elementsEqual(pngSignature)
    }

    private static func isJPEG(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        return data[0] == 0xFF && data[1] == 0xD8
    }

    /// PNG IHDR 파서 (Big-Endian 및 Unaligned 메모리 정렬 안전 파싱)
    private static func parsePNG(_ data: Data, totalSize: Int64) throws -> ImageHeaderMetadata {
        guard data.count >= 24 else { throw BinaryParseError.corruptedPNG }

        let width = data.subdata(in: 16..<20).withUnsafeBytes { ptr -> UInt32 in
            ptr.loadUnaligned(as: UInt32.self).bigEndian
        }
        let height = data.subdata(in: 20..<24).withUnsafeBytes { ptr -> UInt32 in
            ptr.loadUnaligned(as: UInt32.self).bigEndian
        }

        return ImageHeaderMetadata(
            width: Int(width),
            height: Int(height),
            format: "PNG",
            byteSize: totalSize
        )
    }

    /// JPEG SOF0/SOF2 파서 (마커 순회 및 unaligned safe load)
    private static func parseJPEG(_ initialChunk: Data, handle: FileHandle, totalSize: Int64) throws -> ImageHeaderMetadata {
        var data = initialChunk
        var offset = 2

        while true {
            while offset < data.count - 8 {
                guard data[offset] == 0xFF else {
                    offset += 1
                    continue
                }
                let marker = data[offset + 1]
                // SOF0 (0xC0), SOF1 (0xC1), SOF2 (0xC2)
                if marker == 0xC0 || marker == 0xC1 || marker == 0xC2 {
                    let height = data.subdata(in: (offset + 5)..<(offset + 7)).withUnsafeBytes {
                        $0.loadUnaligned(as: UInt16.self).bigEndian
                    }
                    let width = data.subdata(in: (offset + 7)..<(offset + 9)).withUnsafeBytes {
                        $0.loadUnaligned(as: UInt16.self).bigEndian
                    }
                    return ImageHeaderMetadata(
                        width: Int(width),
                        height: Int(height),
                        format: "JPEG",
                        byteSize: totalSize
                    )
                } else if marker == 0xD9 || marker == 0xDA { // EOI or SOS
                    return ImageHeaderMetadata(width: 0, height: 0, format: "JPEG", byteSize: totalSize)
                } else {
                    let length = data.subdata(in: (offset + 2)..<(offset + 4)).withUnsafeBytes {
                        $0.loadUnaligned(as: UInt16.self).bigEndian
                    }
                    offset += 2 + Int(length)
                }
            }

            // 마커를 아직 못 찾았고 추가 데이터가 남아있다면 64KB 추가 적재
            if data.count < totalSize {
                do {
                    guard let nextChunk = try handle.read(upToCount: 65536), !nextChunk.isEmpty else {
                        break
                    }
                    data.append(nextChunk)
                } catch {
                    break
                }
            } else {
                break
            }
        }
        return ImageHeaderMetadata(width: 0, height: 0, format: "JPEG", byteSize: totalSize)
    }

    /// 초경량 Pure-Swift SVG 파서
    private static func parseSVG(fileURL: URL, totalSize: Int64) throws -> ImageHeaderMetadata {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            do {
                try handle.close()
            } catch {
                _ = error
            }
        }
        guard let data = try handle.read(upToCount: 4096), let str = String(data: data, encoding: .utf8) else {
            return ImageHeaderMetadata(width: 0, height: 0, format: "SVG", byteSize: totalSize)
        }

        if let range = str.range(of: "viewBox\\s*=\\s*[\"'][^\"']+[\"']", options: .regularExpression) {
            let snippet = String(str[range])
            let parts = snippet.replacingOccurrences(of: "\"", with: "")
                               .replacingOccurrences(of: "'", with: "")
                               .split(separator: "=").last?
                               .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            if let parts = parts, parts.count == 4,
               let w = Double(parts[2]), let h = Double(parts[3]) {
                return ImageHeaderMetadata(width: Int(w), height: Int(h), format: "SVG", byteSize: totalSize)
            }
        }
        return ImageHeaderMetadata(width: 0, height: 0, format: "SVG", byteSize: totalSize)
    }

    /// 경량 PDF MediaBox 파서
    private static func parsePDF(fileURL: URL, handle: FileHandle, totalSize: Int64) throws -> ImageHeaderMetadata {
        guard let data = try handle.read(upToCount: 4096), let str = String(data: data, encoding: .ascii) else {
            return ImageHeaderMetadata(width: 0, height: 0, format: "PDF", byteSize: totalSize)
        }
        if let range = str.range(of: "/MediaBox\\s*\\[[^\\]]+\\]", options: .regularExpression) {
            let snippet = String(str[range])
            let numbers = snippet.split(separator: "[").last?.replacingOccurrences(of: "]", with: "")
                .split(whereSeparator: { $0.isWhitespace })
                .compactMap { Double($0) }
            if let numbers = numbers, numbers.count == 4 {
                let w = Int(numbers[2] - numbers[0])
                let h = Int(numbers[3] - numbers[1])
                return ImageHeaderMetadata(width: w, height: h, format: "PDF", byteSize: totalSize)
            }
        }
        return ImageHeaderMetadata(width: 0, height: 0, format: "PDF", byteSize: totalSize)
    }

    public enum BinaryParseError: Error {
        case insufficientData
        case corruptedPNG
        case corruptedJPEG
    }
}
