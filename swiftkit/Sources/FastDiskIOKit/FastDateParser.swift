import Foundation

public enum FastDateParser: Sendable {
    private final class CachedFormatters: @unchecked Sendable {
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

    private static let threadKey = "net.ranode.fastdiskio.fastdateparser.formatters"

    private static func currentFormatters() -> CachedFormatters {
        let dict = Thread.current.threadDictionary
        if let existing = dict[threadKey] as? CachedFormatters {
            return existing
        }
        let created = CachedFormatters()
        dict[threadKey] = created
        return created
    }

    public static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatters = currentFormatters()
        if trimmed.contains(".") {
            return formatters.fractional.date(from: trimmed) ?? formatters.standard.date(from: trimmed)
        } else {
            return formatters.standard.date(from: trimmed) ?? formatters.fractional.date(from: trimmed)
        }
    }

    public static func format(_ date: Date, includeFractionalSeconds: Bool = false) -> String {
        let formatters = currentFormatters()
        let formatter = includeFractionalSeconds ? formatters.fractional : formatters.standard
        return formatter.string(from: date)
    }
}
