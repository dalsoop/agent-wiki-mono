import Foundation

extension AntigravitySessionReader {
    @inline(__always)
    static func isPrintableASCII(_ b: UInt8) -> Bool {
        switch b {
        case 0x09, 0x0A, 0x20...0x7E:
            return true
        default:
            return false
        }
    }

    @inline(__always)
    static func validUTF8SequenceLength(ptr: UnsafePointer<UInt8>, index: Int, totalCount: Int) -> Int? {
        let b = ptr[index]
        guard b >= 0xC2, b <= 0xF4 else { return nil }
        let continuationCount: Int
        switch b {
        case 0xC2...0xDF: continuationCount = 1
        case 0xE0...0xEF: continuationCount = 2
        default: continuationCount = 3
        }
        guard index + continuationCount < totalCount else { return nil }
        for c in 1...continuationCount {
            let cb = ptr[index + c]
            guard cb >= 0x80, cb <= 0xBF else { return nil }
        }
        return continuationCount + 1
    }

    /// blob 에서 사람이 읽을 문자열 run 을 뽑는다. printable ASCII + 개행 + **유효한
    /// 멀티바이트 UTF-8** — Antigravity 는 한국어 원문을 raw UTF-8 로 저장하므로
    /// ASCII 만 인정하면 사용자 발언이 전량 유실된다(실측).
    package static func strings(in data: Data, minRunLength: Int = 4) -> [String] {
        guard !data.isEmpty else { return [] }
        var runs: [String] = []
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let count = rawBuffer.count
            var runStart = -1
            var i = 0

            while i < count {
                guard let advance = validAdvanceLength(ptr: ptr, index: i, totalCount: count) else {
                    flushRun(ptr: ptr, start: runStart, end: i, minLength: minRunLength, into: &runs)
                    runStart = -1
                    i += 1
                    continue
                }
                runStart = (runStart < 0) ? i : runStart
                i += advance
            }
            flushRun(ptr: ptr, start: runStart, end: count, minLength: minRunLength, into: &runs)
        }
        return runs
    }

    private static func validAdvanceLength(ptr: UnsafePointer<UInt8>, index: Int, totalCount: Int) -> Int? {
        if isPrintableASCII(ptr[index]) { return 1 }
        return validUTF8SequenceLength(ptr: ptr, index: index, totalCount: totalCount)
    }

    private static func flushRun(
        ptr: UnsafePointer<UInt8>,
        start: Int,
        end: Int,
        minLength: Int,
        into runs: inout [String]
    ) {
        guard start >= 0, end - start >= minLength else { return }
        let subBuffer = UnsafeBufferPointer(start: ptr + start, count: end - start)
        guard let s = String(bytes: subBuffer, encoding: .utf8), s.count >= minLength else { return }
        runs.append(s)
    }
}
