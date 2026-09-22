import Foundation

/// 스레드-세이프 정적 캐시 기반의 제로-할당 날짜/시간 포맷팅 및 파싱 코덱.
///
/// `DateFormatter`와 `ISO8601DateFormatter`의 빈번한 인스턴스화로 인한 CPU 사이클 낭비 및 락 경합을 방지하기 위해
/// Thread-local 캐시를 기반으로 동일 포맷터 인스턴스를 무락(Lock-free)으로 재사용합니다.
public enum DateCodec: Sendable {

    private final class FormatterStore {
        var formatters: [String: DateFormatter] = [:]
        var styleFormatters: [String: DateFormatter] = [:]
    }

    private static let threadKey = "net.ranode.datecodeckit.formatters.store"

    private static func currentStore() -> FormatterStore {
        let dict = Thread.current.threadDictionary
        if let existing = dict[threadKey] as? FormatterStore {
            return existing
        }
        let created = FormatterStore()
        dict[threadKey] = created
        return created
    }

    // MARK: - ISO8601 APIs

    /// ISO8601 문자열(소수 초 포함 또는 미포함)을 Date로 파싱합니다.
    @inlinable
    public static func parseISO8601(_ string: String?) -> Date? {
        ISO8601DateCodec.parse(string)
    }

    /// Date를 ISO8601 문자열로 포맷팅합니다.
    @inlinable
    public static func formatISO8601(_ date: Date, includeFractionalSeconds: Bool = false) -> String {
        ISO8601DateCodec.format(date, includeFractionalSeconds: includeFractionalSeconds)
    }

    /// 현재 시각을 ISO8601 문자열로 반환합니다.
    @inlinable
    public static func isoNow(includeFractionalSeconds: Bool = false) -> String {
        ISO8601DateCodec.format(Date(), includeFractionalSeconds: includeFractionalSeconds)
    }

    // MARK: - DateFormatter Cached Helpers

    /// 지정된 포맷 패턴, 시간대, 로캘에 대해 현재 스레드 전용으로 캐시된 DateFormatter를 반환합니다.
    public static func cachedFormatter(
        format: String,
        timeZone: TimeZone = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> DateFormatter {
        let store = currentStore()
        let cacheKey = "\(format)|\(timeZone.identifier)|\(locale.identifier)"
        if let existing = store.formatters[cacheKey] {
            return existing
        }
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = timeZone
        formatter.locale = locale
        store.formatters[cacheKey] = formatter
        return formatter
    }

    /// 스타일(dateStyle, timeStyle) 기반으로 캐시된 DateFormatter를 반환합니다.
    public static func cachedStyleFormatter(
        dateStyle: DateFormatter.Style = .none,
        timeStyle: DateFormatter.Style = .none,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> DateFormatter {
        let store = currentStore()
        let cacheKey = "\(dateStyle.rawValue)|\(timeStyle.rawValue)|\(timeZone.identifier)|\(locale.identifier)"
        if let existing = store.styleFormatters[cacheKey] {
            return existing
        }
        let formatter = DateFormatter()
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        formatter.timeZone = timeZone
        formatter.locale = locale
        store.styleFormatters[cacheKey] = formatter
        return formatter
    }

    /// 지정된 포맷 패턴, 시간대, 로캘에 대해 캐시된 포맷터의 방어적 복사본(copy)을 생성하여 반환합니다.
    public static func makeFormatter(
        format: String,
        timeZone: TimeZone = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> DateFormatter {
        let cached = cachedFormatter(format: format, timeZone: timeZone, locale: locale)
        guard let copy = cached.copy() as? DateFormatter else {
            let fallback = DateFormatter()
            fallback.dateFormat = format
            fallback.timeZone = timeZone
            fallback.locale = locale
            return fallback
        }
        return copy
    }

    /// 스타일(dateStyle, timeStyle) 기반으로 캐시된 포맷터의 방어적 복사본(copy)을 생성하여 반환합니다.
    public static func makeStyleFormatter(
        dateStyle: DateFormatter.Style = .none,
        timeStyle: DateFormatter.Style = .none,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> DateFormatter {
        let cached = cachedStyleFormatter(dateStyle: dateStyle, timeStyle: timeStyle, timeZone: timeZone, locale: locale)
        guard let copy = cached.copy() as? DateFormatter else {
            let fallback = DateFormatter()
            fallback.dateStyle = dateStyle
            fallback.timeStyle = timeStyle
            fallback.timeZone = timeZone
            fallback.locale = locale
            return fallback
        }
        return copy
    }

    /// 지정된 포맷 패턴으로 Date를 문자열로 포맷팅합니다.
    public static func format(
        _ date: Date,
        format: String,
        timeZone: TimeZone = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        cachedFormatter(format: format, timeZone: timeZone, locale: locale).string(from: date)
    }

    /// 지정된 포맷 패턴으로 날짜 문자열을 파싱합니다.
    public static func parse(
        _ string: String?,
        format: String,
        timeZone: TimeZone = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> Date? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return cachedFormatter(format: format, timeZone: timeZone, locale: locale).date(from: trimmed)
    }

    /// 스타일(dateStyle, timeStyle)을 적용하여 Date를 문자열로 포맷팅합니다.
    public static func format(
        _ date: Date,
        dateStyle: DateFormatter.Style = .none,
        timeStyle: DateFormatter.Style = .none,
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        cachedStyleFormatter(dateStyle: dateStyle, timeStyle: timeStyle, timeZone: timeZone, locale: locale).string(from: date)
    }

    /// 타임스탬프(초 단위)를 지정된 포맷으로 포맷팅합니다 (예: "HH:mm:ss.SSS").
    @inlinable
    public static func formatTimestamp(
        _ timestamp: Double,
        format: String = "HH:mm:ss.SSS",
        timeZone: TimeZone = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        Self.format(Date(timeIntervalSince1970: timestamp), format: format, timeZone: timeZone, locale: locale)
    }

    /// 날짜를 "yyyy-MM-dd" 형식으로 포맷팅합니다.
    @inlinable
    public static func formatDate(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        Self.format(date, format: "yyyy-MM-dd", timeZone: timeZone)
    }

    /// 시각을 "HH:mm:ss" 형식으로 포맷팅합니다.
    @inlinable
    public static func formatTime(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        Self.format(date, format: "HH:mm:ss", timeZone: timeZone)
    }

    /// 날짜 및 시각을 "yyyy-MM-dd HH:mm:ss" 형식으로 포맷팅합니다.
    @inlinable
    public static func formatDateTime(_ date: Date = Date(), timeZone: TimeZone = .current) -> String {
        Self.format(date, format: "yyyy-MM-dd HH:mm:ss", timeZone: timeZone)
    }
}
