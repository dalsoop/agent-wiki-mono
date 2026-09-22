import Foundation

public enum EvaluationCodec {
    public static func encode(_ document: EvaluationDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public static func decode(_ data: Data) throws -> EvaluationDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EvaluationDocument.self, from: data)
    }
}
