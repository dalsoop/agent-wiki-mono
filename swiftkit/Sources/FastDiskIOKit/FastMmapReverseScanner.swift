import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 대용량 로그/파일을 메모리 매핑(mmap)하여 파일 끝(EOF)부터 역방향으로
/// 제로카피 스캔하는 고성능 스캐너.
public struct FastMmapReverseScanner: Sendable {
    public let buffer: MmapBuffer

    /// 지정된 파일 경로를 읽기 전용으로 mmap 매핑하고, 역방향 탐색 최적화를 위해 MADV_RANDOM 힌트를 적용합니다.
    public init(path: String) throws {
        self.buffer = try MmapBuffer(path: path, readOnly: true)
        if let ptr = buffer.pointer, buffer.size > 0 {
            madvise(UnsafeMutableRawPointer(mutating: ptr), buffer.size, MADV_RANDOM)
        }
    }

    /// 기존 MmapBuffer를 전달받아 스캐너를 초기화하며, MADV_RANDOM 힌트를 적용합니다.
    public init(buffer: MmapBuffer) {
        self.buffer = buffer
        if let ptr = buffer.pointer, buffer.size > 0 {
            madvise(UnsafeMutableRawPointer(mutating: ptr), buffer.size, MADV_RANDOM)
        }
    }

    private static func findPreviousNewline(in ptr: UnsafePointer<UInt8>, before: Int) -> (lineStart: Int, foundNewline: Bool) {
        var i = before - 1
        while i >= 0 {
            guard ptr[i] != 0x0A else {
                return (i + 1, true)
            }
            i -= 1
        }
        return (0, false)
    }

    private static func adjustedLineEnd(candidate: Int, start: Int, ptr: UnsafePointer<UInt8>) -> Int {
        let hasCR = candidate > start && ptr[candidate - 1] == 0x0D
        return hasCR ? candidate - 1 : candidate
    }

    /// 파일 끝(EOF)부터 역방향으로 각 라인을 제로카피 바이트 슬라이스 형태로 순회합니다.
    ///
    /// - Parameters:
    ///   - limit: 최대 스캔 라인 수. 0 이하인 경우 즉시 종료합니다.
    ///   - processLine: 각 라인의 바이트 슬라이스(`UnsafeBufferPointer<UInt8>`)를 수신하는 클로저.
    ///                  개행 문자(`\r`, `\n`)는 제외된 상태로 전달됩니다.
    ///                  `false`를 반환하면 스캔이 조기 중단됩니다.
    public func scanReverse(
        limit: Int,
        processLine: (UnsafeBufferPointer<UInt8>) throws -> Bool
    ) rethrows {
        guard limit > 0, buffer.size > 0, let rawPtr = buffer.pointer else { return }

        let ptr = rawPtr.assumingMemoryBound(to: UInt8.self)
        let count = buffer.size
        var cursor = (ptr[count - 1] == 0x0A) ? count - 1 : count
        var linesProcessed = 0

        while linesProcessed < limit {
            let (lineStart, foundNewline) = (cursor > 0)
                ? Self.findPreviousNewline(in: ptr, before: cursor)
                : (0, false)

            let lineEnd = Self.adjustedLineEnd(candidate: cursor, start: lineStart, ptr: ptr)
            let lineBuf = UnsafeBufferPointer(start: ptr + lineStart, count: lineEnd - lineStart)
            linesProcessed += 1

            let shouldContinue = try processLine(lineBuf)
            guard shouldContinue && foundNewline else { break }

            cursor = lineStart - 1
        }
    }

    /// 파일 끝부터 마지막 `limit`개의 라인을 UTF-8 문자열로 추출합니다.
    ///
    /// - Parameters:
    ///   - limit: 최대 추출 라인 수.
    ///   - reversed: `true`인 경우 EOF에 가장 가까운 라인부터 역순으로 정렬하여 반환합니다.
    ///               `false`(기본값)인 경우 파일 원본 순서(정방향)로 정렬하여 반환합니다.
    /// - Returns: 추출된 라인 문자열 배열.
    public func tailLines(limit: Int, reversed: Bool = false) -> [String] {
        guard limit > 0, buffer.size > 0 else { return [] }

        var result: [String] = []
        result.reserveCapacity(min(limit, 1024))

        scanReverse(limit: limit) { lineBuf in
            result.append(String(decoding: lineBuf, as: UTF8.self))
            return true
        }

        if !reversed {
            result.reverse()
        }

        return result
    }

    /// 정적 편의 함수: 파일 경로에서 마지막 `limit`개 라인을 추출합니다.
    public static func tailLines(path: String, limit: Int, reversed: Bool = false) throws -> [String] {
        let scanner = try FastMmapReverseScanner(path: path)
        return scanner.tailLines(limit: limit, reversed: reversed)
    }
}
