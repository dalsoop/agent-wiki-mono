import Foundation
import ISO8601DateCodecKit

public enum ArchitectureIRCodecError: Error, LocalizedError {
    case encodingFailed(String)
    case decodingFailed(String)
    case validationFailed(ValidationReport)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let reason): return "IR 인코딩 실패: \(reason)"
        case .decodingFailed(let reason): return "IR 디코딩 실패: \(reason)"
        case .validationFailed(let report):
            let errs = report.errors.map(\.description).joined(separator: "\n")
            return "IR 유효성 검증 실패:\n\(errs)"
        }
    }
}

public enum ArchitectureIRCodec {
    public static func makeEncoder(pretty: Bool = true) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateCodec.format(date, includeFractionalSeconds: true))
        }
        var formatting: JSONEncoder.OutputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if pretty {
            formatting.insert(.prettyPrinted)
        }
        encoder.outputFormatting = formatting
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = ISO8601DateCodec.parse(str) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "유효하지 않은 ISO8601 날짜 형식: \(str)"
            )
        }
        return decoder
    }

    public static func encode(
        _ document: ArchitectureIRDocument,
        pretty: Bool = true,
        validate: Bool = true
    ) throws -> Data {
        if validate {
            let report = ArchitectureIRValidator.validate(document)
            if !report.isValid {
                throw ArchitectureIRCodecError.validationFailed(report)
            }
        }
        do {
            return try makeEncoder(pretty: pretty).encode(document)
        } catch {
            throw ArchitectureIRCodecError.encodingFailed(error.localizedDescription)
        }
    }

    public static func decode(
        from data: Data,
        validate: Bool = true
    ) throws -> ArchitectureIRDocument {
        let document: ArchitectureIRDocument
        do {
            document = try makeDecoder().decode(ArchitectureIRDocument.self, from: data)
        } catch {
            throw ArchitectureIRCodecError.decodingFailed(error.localizedDescription)
        }
        if validate {
            let report = ArchitectureIRValidator.validate(document)
            if !report.isValid {
                throw ArchitectureIRCodecError.validationFailed(report)
            }
        }
        return document
    }

    public static func decode(
        from string: String,
        validate: Bool = true
    ) throws -> ArchitectureIRDocument {
        guard let data = string.data(using: .utf8) else {
            throw ArchitectureIRCodecError.decodingFailed("UTF-8 인코딩 변환 실패")
        }
        return try decode(from: data, validate: validate)
    }
}
