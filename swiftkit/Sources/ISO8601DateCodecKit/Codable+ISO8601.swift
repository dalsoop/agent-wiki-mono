import Foundation

// MARK: - JSONDecoder Extensions

extension JSONDecoder.DateDecodingStrategy {
    /// 소수 초 유무와 무관하게 표준 및 밀리초 포함 ISO8601 날짜를 자동 감지하여 디코딩하는 유연한 전략.
    public static let iso8601Flexible: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)
        if let date = ISO8601DateCodec.parse(dateString) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected date string to be ISO8601-formatted with or without fractional seconds, but got: '\(dateString)'"
        )
    }
}

extension JSONDecoder {
    /// `.iso8601Flexible` 날짜 디코딩 전략이 사전 구성된 `JSONDecoder` 인스턴스를 반환합니다.
    public static var iso8601Flexible: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601Flexible
        return decoder
    }
}

// MARK: - JSONEncoder Extensions

extension JSONEncoder.DateEncodingStrategy {
    /// 소수 초가 포함된 ISO8601 포맷으로 인코딩하는 유연한 전략.
    public static let iso8601Flexible: JSONEncoder.DateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        let formatted = ISO8601DateCodec.format(date, includeFractionalSeconds: true)
        try container.encode(formatted)
    }

    /// ISO8601 포맷으로 날짜를 인코딩하는 전략을 생성합니다.
    /// - Parameter includeFractionalSeconds: 소수 초 포함 여부 (기본값: false).
    public static func iso8601(includeFractionalSeconds: Bool = false) -> JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatted = ISO8601DateCodec.format(date, includeFractionalSeconds: includeFractionalSeconds)
            try container.encode(formatted)
        }
    }
}

extension JSONEncoder {
    /// `.iso8601Flexible` 날짜 인코딩 전략이 사전 구성된 `JSONEncoder` 인스턴스를 반환합니다.
    public static var iso8601Flexible: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601Flexible
        return encoder
    }
}
