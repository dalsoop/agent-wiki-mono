import Foundation
import Darwin
import FastDiskIOKit

/// jsonl 리더 공용 헬퍼. **Foundation 만** 쓴다 — 이 Core 는 PATH CLI 가 링크하므로
/// AppKit 이 딸려오면 dual-entry 가 행에 걸린다(2026-07-25 사고).
public enum JSONLine {
    /// 한 줄이 이보다 크면 **먼저 거대한 문자열을 털어내고** 다시 시도한다.
    /// codex 세션은 생성 이미지가 base64 로 박혀 한 줄이 수백 KB~MB 가 된다.
    public static let perLineByteCap = 512 * 1024

    /// 이보다 긴 **문자열 값**은 blob 으로 보고 비운다.
    ///
    /// 사람이 쓴 글은 이 길이를 넘지 않는다(넘으면 그건 붙여넣은 파일이다). base64 이미지는
    /// 수백 KB 다. 그 사이에 선을 그으면 구조를 그대로 둔 채 blob 만 뺄 수 있다.
    public static let blobStringByteCap = 64 * 1024

    /// 거대한 문자열 값만 비운 사본. 구조는 그대로라 기존 파서가 그대로 먹는다.
    ///
    /// **왜 필요한가**: 예전엔 큰 줄을 통째로 버렸는데, codex 는 이미지가 붙은
    /// **사용자 지시**를 한 줄에 담는다 — 80자짜리 진짜 지시가 683KB 이미지에 딸려
    /// 통째로 사라졌다(실측: 218MB 세션에서 811줄 중 109줄, 바이트의 99.2%). 이 앱이
    /// 가장 필요로 하는 신호가 바로 그 지시라, 버릴 게 아니라 blob 만 털어야 한다.
    public static func strippingBlobs(_ data: Data, cap: Int = blobStringByteCap) -> Data {
        var out = Data()
        out.reserveCapacity(min(data.count, 1 << 20))
        var i = data.startIndex
        let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
        while i < data.endIndex {
            let b = data[i]
            guard b == quote else { out.append(b); i = data.index(after: i); continue }
            // 문자열 시작 — 이스케이프를 존중하며 끝을 찾는다.
            var j = data.index(after: i)
            var escaped = false
            while j < data.endIndex {
                let c = data[j]
                if escaped { escaped = false }
                else if c == backslash { escaped = true }
                else if c == quote { break }
                j = data.index(after: j)
            }
            guard j < data.endIndex else { out.append(contentsOf: data[i...]); break }
            let inner = data.index(after: i)..<j
            if data.distance(from: inner.lowerBound, to: inner.upperBound) > cap {
                out.append(quote); out.append(quote)      // 빈 문자열로 대체
            } else {
                out.append(contentsOf: data[i...j])
            }
            i = data.index(after: j)
        }
        return out
    }

    public static func object(_ line: some StringProtocol) -> [String: Any]? {
        guard let data = String(line).data(using: .utf8) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    /// 파일을 줄 단위로 흘려보낸다. 전체를 메모리에 올리지 않는다.
    ///
    /// `handle` 이 `false` 를 돌려주면 즉시 멈춘다(앞부분만 필요할 때).
    /// 파일 크기(바이트). 못 읽으면 0.
    public static func fileSize(_ path: String) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) as? Int ?? 0
    }

    /// 파일 **원문 바이트**에 이 문자열이 있는가.
    ///
    /// 일부러 JSON 을 파싱하지 않는다. 찾으려는 건 우리가 방금 심은 표식이고, 그건 어느
    /// 툴의 어떤 봉투에 실리든 바이트로는 그대로 남는다 — 이 판정만은 파서 드리프트에
    /// 걸리지 않아야 한다(툴 스키마는 실제로 계속 바뀐다).
    ///
    /// 처음엔 머리 256KB 만 봤는데, 그러면 **돌던 세션에 팩 경로를 붙여넣은 경우**를 놓친다.
    /// 파일 끝까지(상한까지) 훑되 청크를 이어 붙일 때 표식이 경계에 걸리지 않게 겹쳐 읽는다.
    /// **한 줄 안에** 주어진 조각이 전부 있는가.
    ///
    /// 표식 하나만 보면 "그 이름을 언급한 세션" 과 "그 프롬프트를 받은 세션" 이 구분되지
    /// 않는다(실측 2026-07-28: 인수인계 앱을 개발하던 세션이 팩 파일명을 계속 출력해서
    /// 자기 자신이 인수자로 잡혔다). 우리가 심은 건 **파일명이 아니라 프롬프트**이므로,
    /// 프롬프트 첫 문장과 파일명이 **같은 줄**에 있는지를 본다.
    public static func lineContainsAll(path: String, parts: [String],
                                       maxBytes: Int = 32 * 1024 * 1024) -> Bool {
        let needles = parts.compactMap { $0.isEmpty ? nil : Data($0.utf8) }
        guard needles.count == parts.count, !needles.isEmpty,
              let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? fh.close() }
        var carry = Data()
        var consumed = 0
        let nl = UInt8(ascii: "\n")
        func hit(_ line: Data) -> Bool { needles.allSatisfy { line.range(of: $0) != nil } }
        while consumed < maxBytes {
            if Task.isCancelled { return false }
            guard let chunk = try? fh.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            consumed += chunk.count
            carry.append(chunk)
            while let i = carry.firstIndex(of: nl) {
                let line = carry.subdata(in: carry.startIndex..<i)
                carry = carry.subdata(in: carry.index(after: i)..<carry.endIndex)
                if hit(line) { return true }
            }
            // 한 줄이 지나치게 길면(이미지 blob) 그 줄만 흘려보낸다.
            if carry.count > perLineByteCap * 4 {
                if hit(carry) { return true }
                carry.removeAll(keepingCapacity: true)
            }
        }
        return !carry.isEmpty && hit(carry)
    }

    public static func contains(path: String, marker: String, maxBytes: Int = 32 * 1024 * 1024) -> Bool {
        guard !marker.isEmpty, let needle = marker.data(using: .utf8),
              let fh = FileHandle(forReadingAtPath: path)
        else { return false }
        defer { try? fh.close() }
        var overlap = Data()
        var consumed = 0
        while consumed < maxBytes {
            if Task.isCancelled { return false }
            guard let chunk = try? fh.read(upToCount: 1 << 20), !chunk.isEmpty else { break }
            consumed += chunk.count
            var window = overlap
            window.append(chunk)
            if window.range(of: needle) != nil { return true }
            // 다음 청크와의 경계에서 잘린 표식을 놓치지 않을 만큼만 남긴다.
            overlap = window.suffix(needle.count - 1)
        }
        return false
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

    /// - Parameter from: 여기서부터 읽는다. 0 이 아니면 **첫 부분 줄은 버린다** —
    ///   임의 오프셋은 줄 중간에 떨어지므로 잘린 JSON 을 파싱하면 안 된다.
    public static func forEachLine(
        path: String,
        from offset: Int = 0,
        maxBytes: Int = 64 * 1024 * 1024,
        matchingTokens: [Data] = [],
        _ handle: ([String: Any]) -> Bool
    ) {
        JSONLineFastScan.forEachLine(
            path: path,
            from: offset,
            maxBytes: maxBytes,
            matchingTokens: matchingTokens,
            handle
        )
    }

    static func parseJSONDict(_ data: Data) -> [String: Any]? {
        let usable = data.count <= perLineByteCap ? data : strippingBlobs(data)
        guard usable.count <= perLineByteCap else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: usable) as? [String: Any]
        } catch {
            return nil
        }
    }

    public static func string(_ v: Any?) -> String? {
        guard let s = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    /// ISO8601 (소수점 초 있든 없든) 파싱.
    public static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }
}
