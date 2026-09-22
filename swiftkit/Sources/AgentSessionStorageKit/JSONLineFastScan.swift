import Foundation
import Darwin
import FastDiskIOKit

/// Fast streaming engine for JSONL session inspection using mmap and memchr.
enum JSONLineFastScan {
    static func forEachLine(
        path: String,
        from offset: Int = 0,
        maxBytes: Int = 64 * 1024 * 1024,
        matchingTokens: [Data] = [],
        _ handle: ([String: Any]) -> Bool
    ) {
        do {
            let mmap = try MmapBuffer(path: path, readOnly: true)
            if mmap.size > 0, let base = mmap.pointer {
                forEachLineMmap(
                    mmap: mmap,
                    base: base,
                    offset: offset,
                    maxBytes: maxBytes,
                    matchingTokens: matchingTokens,
                    handle
                )
                return
            }
        } catch let err {
            _ = err // MmapBuffer 실패 시 FileHandle 폴백 진행
        }

        forEachLineFileHandle(path: path, offset: offset, maxBytes: maxBytes, matchingTokens: matchingTokens, handle)
    }

    private static func forEachLineMmap(
        mmap: MmapBuffer,
        base: UnsafeRawPointer,
        offset: Int,
        maxBytes: Int,
        matchingTokens: [Data],
        _ handle: ([String: Any]) -> Bool
    ) {
        let totalSize = mmap.size
        let startOffset = max(0, min(offset, totalSize))
        let endOffset = min(totalSize, startOffset + maxBytes)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        var current = startOffset
        var droppedPartialLine = offset == 0

        while current < endOffset {
            if Task.isCancelled { return }
            let remaining = endOffset - current
            let lineStartPtr = ptr.advanced(by: current)
            guard let nlPtr = Darwin.memchr(lineStartPtr, Int32(UInt8(ascii: "\n")), remaining) else {
                handleMmapTail(
                    lineStartPtr: lineStartPtr,
                    remaining: remaining,
                    droppedPartialLine: droppedPartialLine,
                    matchingTokens: matchingTokens,
                    handle
                )
                break
            }

            let nlDistance = ptr.distance(to: nlPtr.assumingMemoryBound(to: UInt8.self)) - current
            current += (nlDistance + 1)

            guard droppedPartialLine else {
                droppedPartialLine = true
                continue
            }

            guard nlDistance > 0, matchesAny(lineStart: lineStartPtr, lineLen: nlDistance, tokens: matchingTokens) else {
                continue
            }

            let lineData = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: lineStartPtr), count: nlDistance, deallocator: .none)
            guard let o = JSONLine.parseJSONDict(lineData) else { continue }
            if !handle(o) { return }
        }
    }

    private static func handleMmapTail(
        lineStartPtr: UnsafePointer<UInt8>,
        remaining: Int,
        droppedPartialLine: Bool,
        matchingTokens: [Data],
        _ handle: ([String: Any]) -> Bool
    ) {
        guard droppedPartialLine && remaining > 0 else { return }
        guard matchesAny(lineStart: lineStartPtr, lineLen: remaining, tokens: matchingTokens) else { return }
        let lineData = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: lineStartPtr), count: remaining, deallocator: .none)
        if let o = JSONLine.parseJSONDict(lineData) {
            _ = handle(o)
        }
    }

    private static func forEachLineFileHandle(
        path: String,
        offset: Int,
        maxBytes: Int,
        matchingTokens: [Data],
        _ handle: ([String: Any]) -> Bool
    ) {
        guard let fh = FileHandle(forReadingAtPath: path) else { return }
        defer { try? fh.close() }
        var carry = Data()
        var consumed = 0
        var droppedPartialLine = offset == 0
        if offset > 0 { try? fh.seek(toOffset: UInt64(offset)) }

        while consumed < maxBytes {
            if Task.isCancelled { return }
            guard let chunk = try? fh.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            consumed += chunk.count
            carry.append(chunk)

            let keepGoing = processCarryBuffer(&carry, &droppedPartialLine, matchingTokens, handle)
            guard keepGoing else { return }
        }

        processCarryTail(carry, matchingTokens, handle)
    }

    private static func processCarryBuffer(
        _ carry: inout Data,
        _ droppedPartialLine: inout Bool,
        _ matchingTokens: [Data],
        _ handle: ([String: Any]) -> Bool
    ) -> Bool {
        while let nl = carry.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = carry.subdata(in: carry.startIndex..<nl)
            carry = carry.subdata(in: carry.index(after: nl)..<carry.endIndex)

            guard droppedPartialLine else { droppedPartialLine = true; continue }
            guard !lineData.isEmpty, matchesTokenFilter(data: lineData, tokens: matchingTokens) else { continue }
            guard let o = JSONLine.parseJSONDict(lineData) else { continue }
            if !handle(o) { return false }
        }
        return true
    }

    private static func processCarryTail(
        _ carry: Data,
        _ matchingTokens: [Data],
        _ handle: ([String: Any]) -> Bool
    ) {
        guard !carry.isEmpty, matchesTokenFilter(data: carry, tokens: matchingTokens) else { return }
        if let o = JSONLine.parseJSONDict(carry) {
            _ = handle(o)
        }
    }

    private static func matchesTokenFilter(data: Data, tokens: [Data]) -> Bool {
        guard !tokens.isEmpty else { return true }
        var matched = false
        data.withUnsafeBytes { lineBuf in
            guard let lineBase = lineBuf.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            matched = matchesAny(lineStart: lineBase, lineLen: data.count, tokens: tokens)
        }
        return matched
    }

    @inline(__always)
    private static func tokenMatches(token: Data, lineStart: UnsafePointer<UInt8>, lineLen: Int) -> Bool {
        guard !token.isEmpty, token.count <= lineLen else { return false }
        let found = token.withUnsafeBytes { tokenBuf -> UnsafeMutableRawPointer? in
            guard let tokenBase = tokenBuf.baseAddress else { return nil }
            return Darwin.memmem(lineStart, lineLen, tokenBase, token.count)
        }
        return found != nil
    }

    @inline(__always)
    private static func matchesAny(lineStart: UnsafePointer<UInt8>, lineLen: Int, tokens: [Data]) -> Bool {
        guard !tokens.isEmpty else { return true }
        return tokens.contains { tokenMatches(token: $0, lineStart: lineStart, lineLen: lineLen) }
    }
}
