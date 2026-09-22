import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FastFileReader: Sendable {
    public static func readTailLines(
        path: String,
        maxLines: Int,
        maxBytes: Int = 1024 * 1024
    ) throws -> [Substring] {
        guard maxLines > 0 else { return [] }

        let fd = open(path, O_RDONLY)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }

        let endOffset = lseek(fd, 0, SEEK_END)
        guard endOffset > 0 else { return [] }

        let bytesToRead = Int(min(endOffset, off_t(maxBytes)))
        let startOffset = endOffset - off_t(bytesToRead)

        var buffer = [UInt8](repeating: 0, count: bytesToRead)
        let readCount = pread(fd, &buffer, bytesToRead, startOffset)
        guard readCount > 0 else { return [] }

        var trimmedEnd = readCount
        if trimmedEnd > 0 && buffer[trimmedEnd - 1] == 0x0A { // '\n'
            trimmedEnd -= 1
            if trimmedEnd > 0 && buffer[trimmedEnd - 1] == 0x0D { // '\r'
                trimmedEnd -= 1
            }
        }

        guard trimmedEnd > 0 else { return [] }

        var newlinesFound = 0
        var startIndex = 0
        let targetNewlines = maxLines

        if targetNewlines > 0 {
            var i = trimmedEnd - 1
            while i >= 0 {
                if buffer[i] == 0x0A {
                    newlinesFound += 1
                    if newlinesFound == targetNewlines {
                        startIndex = i + 1
                        break
                    }
                }
                i -= 1
            }
        }

        if startOffset > 0 && startIndex == 0 {
            // If we started mid-file and have no initial newline, skip any split UTF-8 continuation byte
            while startIndex < trimmedEnd && (buffer[startIndex] & 0xC0) == 0x80 {
                startIndex += 1
            }
        }

        let slice = buffer[startIndex..<trimmedEnd]
        let string = String(decoding: slice, as: UTF8.self)
        let rawLines = string.split(separator: "\n", omittingEmptySubsequences: false)
        let cleanedLines: [Substring] = rawLines.map { line in
            line.hasSuffix("\r") ? line.dropLast() : line
        }

        if cleanedLines.count > maxLines {
            return Array(cleanedLines.suffix(maxLines))
        }
        return cleanedLines
    }

    public static func readAppendChunk(
        path: String,
        fromOffset: Int64,
        maxBytes: Int = 16 * 1024 * 1024
    ) throws -> (data: Data, newOffset: Int64) {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }

        let fileSize = Int64(lseek(fd, 0, SEEK_END))
        guard fileSize >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        if fileSize < fromOffset {
            // File was truncated or rotated; reset to beginning
            let bytesToRead = Int(min(fileSize, Int64(maxBytes)))
            guard bytesToRead > 0 else {
                return (Data(), 0)
            }
            var data = Data(count: bytesToRead)
            let bytesRead = data.withUnsafeMutableBytes { buf in
                pread(fd, buf.baseAddress, bytesToRead, 0)
            }
            guard bytesRead >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return (data.prefix(bytesRead), Int64(bytesRead))
        }

        if fileSize == fromOffset {
            return (Data(), fromOffset)
        }

        let start = max(Int64(0), fromOffset)
        let bytesToRead = Int(min(fileSize - start, Int64(maxBytes)))
        var data = Data(count: bytesToRead)
        let bytesRead = data.withUnsafeMutableBytes { buf in
            pread(fd, buf.baseAddress, bytesToRead, off_t(start))
        }
        guard bytesRead >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return (data.prefix(bytesRead), start + Int64(bytesRead))
    }

    public static func forEachLine(
        path: String,
        _ handler: (UnsafeBufferPointer<UInt8>) throws -> Bool
    ) throws {
        let mmapBuffer = try MmapBuffer(path: path, readOnly: true)
        guard mmapBuffer.size > 0, let base = mmapBuffer.pointer else { return }

        let ptr = base.assumingMemoryBound(to: UInt8.self)
        let count = mmapBuffer.size
        var lineStart = 0

        for i in 0..<count {
            if ptr[i] == 0x0A { // '\n'
                var lineEnd = i
                if lineEnd > lineStart && ptr[lineEnd - 1] == 0x0D { // '\r'
                    lineEnd -= 1
                }
                let lineBuf = UnsafeBufferPointer(start: ptr + lineStart, count: lineEnd - lineStart)
                let keepGoing = try handler(lineBuf)
                if !keepGoing { return }
                lineStart = i + 1
            }
        }

        if lineStart < count {
            var lineEnd = count
            if lineEnd > lineStart && ptr[lineEnd - 1] == 0x0D {
                lineEnd -= 1
            }
            let lineBuf = UnsafeBufferPointer(start: ptr + lineStart, count: lineEnd - lineStart)
            _ = try handler(lineBuf)
        }
    }

    /// Reads entire file data using mmap or pread fast path.
    public static func readData(at path: String) -> Data? {
        do {
            let mmap = try MmapBuffer(path: path, readOnly: true)
            if mmap.size > 0 {
                return mmap.data
            }
        } catch {}
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let size = lseek(fd, 0, SEEK_END)
        guard size >= 0 else { return nil }
        if size == 0 { return Data() }
        var data = Data(count: Int(size))
        let readCount = data.withUnsafeMutableBytes { buf in
            pread(fd, buf.baseAddress, Int(size), 0)
        }
        guard readCount == size else { return nil }
        return data
    }

    /// Convenience alias for readData(at:)
    public static func read(_ path: String) -> Data? {
        readData(at: path)
    }

    public static func read(path: String) -> Data? {
        readData(at: path)
    }
}
