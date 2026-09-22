import Foundation

extension JSONLine {
    /// 거대한 문자열 값을 **앞부분만** 남긴 사본. `strippingBlobs` 가 값을 비우는 자리와
    /// 같고, grok 스트림처럼 본문 첫 줄은 필요하되 `tool_use` 의 `name`·`id` 는 짧아서
    /// 잘리면 안 되는 줄을 읽을 때 쓴다.
    public static func clippingBlobs(_ data: Data, cap: Int = blobStringByteCap) -> Data {
        var out = Data()
        out.reserveCapacity(min(data.count, 1 << 20))
        var i = data.startIndex
        let quote = UInt8(ascii: "\""), backslash = UInt8(ascii: "\\")
        while i < data.endIndex {
            let b = data[i]
            guard b == quote else { out.append(b); i = data.index(after: i); continue }
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
            let innerLen = data.distance(from: inner.lowerBound, to: inner.upperBound)
            guard innerLen > cap else {
                out.append(contentsOf: data[i...j])
                i = data.index(after: j)
                continue
            }
            let take = clipEnd(data, inner: inner, cap: cap, backslash: backslash)
            out.append(quote)
            if take > 0 {
                let end = data.index(inner.lowerBound, offsetBy: take)
                out.append(contentsOf: data[inner.lowerBound..<end])
            }
            out.append(quote)
            i = data.index(after: j)
        }
        return out
    }

    private static func clipEnd(
        _ data: Data,
        inner: Range<Data.Index>,
        cap: Int,
        backslash: UInt8
    ) -> Int {
        var take = cap
        while take > 0 {
            let end = data.index(inner.lowerBound, offsetBy: take)
            let last = data[data.index(before: end)]
            let safeASCII = last < 0x80 && last != backslash
            let charStart = last >= 0xC0
            if safeASCII || charStart { break }
            take -= 1
        }
        return take
    }
}
