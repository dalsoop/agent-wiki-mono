import Foundation

/// 소수 초(.123Z) 및 표준 ISO8601 문자열과 Date 간의 안전하고 빠른 상호 변환을 지원하는 무락(Lock-free) 코덱.
public enum ISO8601DateCodec: Sendable {
    private final class FormatterPair {
        let fractional: ISO8601DateFormatter
        let standard: ISO8601DateFormatter

        init() {
            let frac = ISO8601DateFormatter()
            frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.fractional = frac

            let std = ISO8601DateFormatter()
            std.formatOptions = [.withInternetDateTime]
            self.standard = std
        }
    }

    private static func cachedPair() -> FormatterPair {
        let key = "net.ranode.iso8601datecodec.formatters"
        let dict = Thread.current.threadDictionary
        if let existing = dict[key] as? FormatterPair {
            return existing
        }
        let created = FormatterPair()
        dict[key] = created
        return created
    }

    /// ISO8601 문자열(소수 초 포함 또는 미포함)을 Date로 파싱합니다.
    /// - Parameter string: 파싱할 날짜 문자열
    /// - Returns: 유효한 Date 또는 nil
    public static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return parseTrimmed(trimmed, using: cachedPair())
    }

    private static func parseTrimmed(_ text: String, using pair: FormatterPair) -> Date? {
        if text.contains(".") {
            return pair.fractional.date(from: text) ?? pair.standard.date(from: text)
        }
        return pair.standard.date(from: text) ?? pair.fractional.date(from: text)
    }

    /// Date를 ISO8601 문자열로 포맷팅합니다.
    /// - Parameters:
    ///   - date: 포맷할 Date
    ///   - includeFractionalSeconds: 밀리초 포함 여부 (기본값: false)
    /// - Returns: ISO8601 형식의 문자열
    public static func format(_ date: Date, includeFractionalSeconds: Bool = false) -> String {
        let pair = cachedPair()
        let formatter = includeFractionalSeconds ? pair.fractional : pair.standard
        return formatter.string(from: date)
    }

    /// `format`과 동일한 ISO8601 포맷팅 편의 별칭.
    @inlinable
    public static func formatISO8601(_ date: Date, includeFractionalSeconds: Bool = false) -> String {
        format(date, includeFractionalSeconds: includeFractionalSeconds)
    }

    /// `parse`와 동일한 ISO8601 파싱 편의 별칭.
    @inlinable
    public static func parseISO8601(_ string: String?) -> Date? {
        parse(string)
    }

    /// 현재 시각을 ISO8601 문자열로 포맷팅하여 반환합니다.
    @inlinable
    public static func isoNow(includeFractionalSeconds: Bool = false) -> String {
        format(Date(), includeFractionalSeconds: includeFractionalSeconds)
    }
}
