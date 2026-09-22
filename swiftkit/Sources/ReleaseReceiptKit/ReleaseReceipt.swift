import Foundation

/// Release artifact metadata representing physical file checksum and size.
public struct ArtifactReceipt: Codable, Sendable, Equatable {
    public let filename: String
    public let sha256: String
    public let sizeBytes: Int64
    public let contentType: String

    public var isValidSHA256: Bool {
        guard sha256.count == 64 else { return false }
        return sha256.allSatisfy { $0.isHexDigit }
    }

    public init(
        filename: String,
        sha256: String,
        sizeBytes: Int64,
        contentType: String
    ) {
        self.filename = filename
        self.sha256 = sha256.lowercased()
        self.sizeBytes = sizeBytes
        self.contentType = contentType
    }
}

/// Apple Notary Service submission and timestamp details.
public struct NotaryReceipt: Codable, Sendable, Equatable {
    public let submissionID: String
    public let notarizedAt: Date
    public let teamID: String?

    public init(
        submissionID: String,
        notarizedAt: Date,
        teamID: String? = nil
    ) {
        self.submissionID = submissionID
        self.notarizedAt = notarizedAt
        self.teamID = teamID
    }

    public static func == (lhs: NotaryReceipt, rhs: NotaryReceipt) -> Bool {
        lhs.submissionID == rhs.submissionID &&
        abs(lhs.notarizedAt.timeIntervalSince1970 - rhs.notarizedAt.timeIntervalSince1970) < 0.001 &&
        lhs.teamID == rhs.teamID
    }
}

/// Sparkle update feed signature details.
public struct SparkleReceipt: Codable, Sendable, Equatable {
    public let ed25519Signature: String?

    public init(ed25519Signature: String? = nil) {
        self.ed25519Signature = ed25519Signature
    }
}

/// Immutable, cryptographically verifiable release receipt for app distribution.
public struct ReleaseReceipt: Codable, Sendable, Equatable {
    private static let schemaDomain = "gujo" + ".ai"
    public static let defaultSchema = "https://\(schemaDomain)/schemas/release-receipt-v1.json"

    public let schema: String
    public let appSlug: String
    public let bundleID: String
    public let version: String
    public let buildNumber: Int?
    public let artifact: ArtifactReceipt
    public let notary: NotaryReceipt
    public let sparkle: SparkleReceipt?
    public let createdAt: Date

    public init(
        schema: String = ReleaseReceipt.defaultSchema,
        appSlug: String,
        bundleID: String,
        version: String,
        buildNumber: Int? = nil,
        artifact: ArtifactReceipt,
        notary: NotaryReceipt,
        sparkle: SparkleReceipt? = nil,
        createdAt: Date = Date()
    ) {
        self.schema = schema
        self.appSlug = appSlug
        self.bundleID = bundleID
        self.version = version
        self.buildNumber = buildNumber
        self.artifact = artifact
        self.notary = notary
        self.sparkle = sparkle
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaDollar = "$schema"
        case appSlug
        case bundleID
        case version
        case buildNumber
        case artifact
        case notary
        case sparkle
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Allow both "$schema" and "schema" keys, with default fallback
        if let explicitSchema = try container.decodeIfPresent(String.self, forKey: .schema) {
            self.schema = explicitSchema
        } else if let dollarSchema = try container.decodeIfPresent(String.self, forKey: .schemaDollar) {
            self.schema = dollarSchema
        } else {
            self.schema = Self.defaultSchema
        }

        self.appSlug = try container.decode(String.self, forKey: .appSlug)
        self.bundleID = try container.decode(String.self, forKey: .bundleID)
        self.version = try container.decode(String.self, forKey: .version)
        self.buildNumber = try container.decodeIfPresent(Int.self, forKey: .buildNumber)
        self.artifact = try container.decode(ArtifactReceipt.self, forKey: .artifact)
        self.notary = try container.decode(NotaryReceipt.self, forKey: .notary)
        self.sparkle = try container.decodeIfPresent(SparkleReceipt.self, forKey: .sparkle)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Store canonical "$schema" and "schema"
        try container.encode(schema, forKey: .schemaDollar)
        try container.encode(schema, forKey: .schema)
        try container.encode(appSlug, forKey: .appSlug)
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(buildNumber, forKey: .buildNumber)
        try container.encode(artifact, forKey: .artifact)
        try container.encode(notary, forKey: .notary)
        try container.encodeIfPresent(sparkle, forKey: .sparkle)
        try container.encode(createdAt, forKey: .createdAt)
    }

    public static func == (lhs: ReleaseReceipt, rhs: ReleaseReceipt) -> Bool {
        lhs.schema == rhs.schema &&
        lhs.appSlug == rhs.appSlug &&
        lhs.bundleID == rhs.bundleID &&
        lhs.version == rhs.version &&
        lhs.buildNumber == rhs.buildNumber &&
        lhs.artifact == rhs.artifact &&
        lhs.notary == rhs.notary &&
        lhs.sparkle == rhs.sparkle &&
        abs(lhs.createdAt.timeIntervalSince1970 - rhs.createdAt.timeIntervalSince1970) < 0.001
    }
}

// MARK: - JSON Encoding & Decoding Helpers

extension ReleaseReceipt {
    private static func makeISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func makeISO8601WithMillisFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    public static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let formatter = makeISO8601WithMillisFormatter()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let dateString = formatter.string(from: date)
            try container.encode(dateString)
        }
        return encoder
    }

    public static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let withMillisFormatter = makeISO8601WithMillisFormatter()
        let standardFormatter = makeISO8601Formatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = withMillisFormatter.date(from: dateString) {
                return date
            }
            if let date = standardFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString). Expected ISO-8601 format."
            )
        }
        return decoder
    }

    public func toJSONData() throws -> Data {
        try Self.makeJSONEncoder().encode(self)
    }

    public func toJSONString() throws -> String {
        let data = try toJSONData()
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(codingPath: [], debugDescription: "Unable to encode JSON data as UTF-8 string")
            )
        }
        return string
    }

    public static func from(jsonData: Data) throws -> ReleaseReceipt {
        try makeJSONDecoder().decode(ReleaseReceipt.self, from: jsonData)
    }

    public static func from(jsonString: String) throws -> ReleaseReceipt {
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: [], debugDescription: "Invalid UTF-8 string input")
            )
        }
        return try from(jsonData: data)
    }

    public static func from(fileURL: URL) throws -> ReleaseReceipt {
        let data = try Data(contentsOf: fileURL)
        return try from(jsonData: data)
    }
}
