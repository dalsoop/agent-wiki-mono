import Foundation

extension _YAMLEncoderImpl {
    /// Encodable을 이 인코더 자신에게 인코딩시켜 `value` 를 채운다.
    /// Date/Data/URL 특수 처리를 거친다.
    func boxInto(_ encodable: Encodable) throws {
        if let date = encodable as? Date {
            value = try boxDateOnly(date)
            return
        }
        if let data = encodable as? Data {
            value = try boxDataOnly(data)
            return
        }
        if let url = encodable as? URL {
            value = .scalar(raw: url.absoluteString, plain: false)
            return
        }
        try encodable.encode(to: self)
    }

    private func boxDateOnly(_ date: Date) throws -> YAMLNode {
        switch dateStrategy {
        case .deferredToDate:
            let ts = date.timeIntervalSince1970
            return .scalar(raw: NumberFormatter.scalar.doubleString(ts), plain: true)
        case .iso8601:
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return .scalar(raw: f.string(from: date), plain: false)
        case .formatted(let formatter):
            return .scalar(raw: formatter.string(from: date), plain: false)
        }
    }

    private func boxDataOnly(_ data: Data) throws -> YAMLNode {
        .scalar(raw: data.base64EncodedString(), plain: false)
    }
}
