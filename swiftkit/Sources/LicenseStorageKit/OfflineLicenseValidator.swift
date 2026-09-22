#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation

/// JSON+EdDSA 오프라인 라이선스 파일 모델.
public struct OfflineLicenseFile: Codable, Sendable, Equatable {
    public var bundleId: String
    public var plan: String
    public var customer: String?
    public var issuedAt: Date
    public var expiresAt: Date?
    public var signature: String
    public var customClaims: [String: String]?

    public init(
        bundleId: String,
        plan: String = "standard",
        customer: String? = nil,
        issuedAt: Date = Date(),
        expiresAt: Date? = nil,
        signature: String = "",
        customClaims: [String: String]? = nil
    ) {
        self.bundleId = bundleId
        self.plan = plan
        self.customer = customer
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.signature = signature
        self.customClaims = customClaims
    }

    /// 서명 대상 결정론적 페이로드 데이터.
    public var payloadData: Data {
        var parts: [String] = [
            bundleId,
            plan,
            customer ?? "",
            String(Int64(issuedAt.timeIntervalSince1970))
        ]
        if let exp = expiresAt {
            parts.append(String(Int64(exp.timeIntervalSince1970)))
        } else {
            parts.append("")
        }
        if let claims = customClaims, !claims.isEmpty {
            let sortedKeys = claims.keys.sorted()
            let pairs = sortedKeys.map { "\($0)=\(claims[$0] ?? "")" }
            parts.append(pairs.joined(separator: ";"))
        }
        return Data(parts.joined(separator: "|").utf8)
    }

    enum CodingKeys: String, CodingKey {
        case bundleId
        case bundleIdentifier
        case productIdentifier
        case product
        case plan
        case planIdentifier
        case customer
        case customerIdentifier
        case issuedAt
        case issued_at
        case expiresAt
        case expires_at
        case signature
        case customClaims
        case claims
        case payload
        case token
    }

    private static func tryDecode<T: Decodable>(_ type: T.Type, from container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> T? {
        do {
            return try container.decode(type, forKey: key)
        } catch {
            return nil
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 1. sl1 토큰 포맷 ("sl1.payload.signature") 지원
        if let token = Self.tryDecode(String.self, from: container, key: .token) {
            let parsed = try Self.parseSl1Token(token)
            self = parsed
            return
        }

        // 2. 래핑된 payload 지원
        if container.contains(.payload) {
            let nested = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .payload)
            let bId = Self.tryDecode(String.self, from: nested, key: .bundleId)
                ?? Self.tryDecode(String.self, from: nested, key: .bundleIdentifier)
                ?? Self.tryDecode(String.self, from: nested, key: .productIdentifier)
                ?? Self.tryDecode(String.self, from: nested, key: .product)
                ?? ""
            let pl = Self.tryDecode(String.self, from: nested, key: .plan)
                ?? Self.tryDecode(String.self, from: nested, key: .planIdentifier)
                ?? "standard"
            let cust = Self.tryDecode(String.self, from: nested, key: .customer)
                ?? Self.tryDecode(String.self, from: nested, key: .customerIdentifier)
            let iss = Self.tryDecode(Date.self, from: nested, key: .issuedAt)
                ?? Self.tryDecode(Date.self, from: nested, key: .issued_at)
                ?? Date()
            let exp = Self.tryDecode(Date.self, from: nested, key: .expiresAt)
                ?? Self.tryDecode(Date.self, from: nested, key: .expires_at)
            let sig = Self.tryDecode(String.self, from: container, key: .signature) ?? ""
            let claims = Self.tryDecode([String: String].self, from: nested, key: .customClaims)
                ?? Self.tryDecode([String: String].self, from: nested, key: .claims)
            self.bundleId = bId
            self.plan = pl
            self.customer = cust
            self.issuedAt = iss
            self.expiresAt = exp
            self.signature = sig
            self.customClaims = claims
            return
        }

        // 3. 플랫 JSON 포맷
        self.bundleId = Self.tryDecode(String.self, from: container, key: .bundleId)
            ?? Self.tryDecode(String.self, from: container, key: .bundleIdentifier)
            ?? Self.tryDecode(String.self, from: container, key: .productIdentifier)
            ?? Self.tryDecode(String.self, from: container, key: .product)
            ?? ""
        self.plan = Self.tryDecode(String.self, from: container, key: .plan)
            ?? Self.tryDecode(String.self, from: container, key: .planIdentifier)
            ?? "standard"
        self.customer = Self.tryDecode(String.self, from: container, key: .customer)
            ?? Self.tryDecode(String.self, from: container, key: .customerIdentifier)

        // 날짜 파싱 (Date 또는 ISO8601 문자열 또는 초/밀리초 숫자)
        if let d = Self.tryDecode(Date.self, from: container, key: .issuedAt) {
            self.issuedAt = d
        } else if let d = Self.tryDecode(Date.self, from: container, key: .issued_at) {
            self.issuedAt = d
        } else if let s = Self.tryDecode(String.self, from: container, key: .issuedAt), let d = Self.date(from: s) {
            self.issuedAt = d
        } else if let num = Self.tryDecode(Double.self, from: container, key: .issuedAt) {
            self.issuedAt = num > 10_000_000_000 ? Date(timeIntervalSince1970: num / 1000) : Date(timeIntervalSince1970: num)
        } else {
            self.issuedAt = Date()
        }

        if let d = Self.tryDecode(Date.self, from: container, key: .expiresAt) {
            self.expiresAt = d
        } else if let d = Self.tryDecode(Date.self, from: container, key: .expires_at) {
            self.expiresAt = d
        } else if let s = Self.tryDecode(String.self, from: container, key: .expiresAt), let d = Self.date(from: s) {
            self.expiresAt = d
        } else if let num = Self.tryDecode(Double.self, from: container, key: .expiresAt) {
            self.expiresAt = num > 10_000_000_000 ? Date(timeIntervalSince1970: num / 1000) : Date(timeIntervalSince1970: num)
        } else {
            self.expiresAt = nil
        }

        self.signature = Self.tryDecode(String.self, from: container, key: .signature) ?? ""
        self.customClaims = Self.tryDecode([String: String].self, from: container, key: .customClaims)
            ?? Self.tryDecode([String: String].self, from: container, key: .claims)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleId, forKey: .bundleId)
        try container.encode(plan, forKey: .plan)
        try container.encodeIfPresent(customer, forKey: .customer)
        try container.encode(issuedAt, forKey: .issuedAt)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
        try container.encode(signature, forKey: .signature)
        try container.encodeIfPresent(customClaims, forKey: .customClaims)
    }

    private static func date(from string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: string) { return d }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter.date(from: string)
    }

    private static func parseSl1Token(_ token: String) throws -> OfflineLicenseFile {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "sl1",
              let payloadData = Data(base64URLOrStandard: String(parts[1])) else {
            throw OfflineLicenseError.invalidFormat("잘못된 sl1 라이선스 토큰입니다.")
        }
        let rawObject: Any
        do {
            rawObject = try JSONSerialization.jsonObject(with: payloadData)
        } catch {
            throw OfflineLicenseError.invalidFormat("잘못된 sl1 라이선스 토큰입니다.")
        }
        guard let json = rawObject as? [String: Any] else {
            throw OfflineLicenseError.invalidFormat("잘못된 sl1 라이선스 토큰입니다.")
        }
        let bId = (json["productIdentifier"] as? String) ?? (json["bundleId"] as? String) ?? ""
        let plan = (json["planIdentifier"] as? String) ?? (json["plan"] as? String) ?? "standard"
        let cust = (json["customerIdentifier"] as? String) ?? (json["customer"] as? String)
        let sig = String(parts[2])
        var iss = Date()
        if let ts = json["issuedAt"] as? Double {
            iss = ts > 10_000_000_000 ? Date(timeIntervalSince1970: ts / 1000) : Date(timeIntervalSince1970: ts)
        }
        var exp: Date?
        if let ts = json["expiresAt"] as? Double {
            exp = ts > 10_000_000_000 ? Date(timeIntervalSince1970: ts / 1000) : Date(timeIntervalSince1970: ts)
        }
        return OfflineLicenseFile(
            bundleId: bId,
            plan: plan,
            customer: cust,
            issuedAt: iss,
            expiresAt: exp,
            signature: sig
        )
    }
}

public enum OfflineLicenseError: Error, LocalizedError, Equatable {
    case invalidFormat(String)
    case invalidSignature
    case invalidPublicKey
    case expired
    case bundleMismatch(expected: String, actual: String)
    case fileNotFound(String)
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let reason):
            return "오프라인 라이선스 파일 형식이 올바르지 않습니다: \(reason)"
        case .invalidSignature:
            return "오프라인 라이선스 서명을 확인할 수 없습니다."
        case .invalidPublicKey:
            return "오프라인 라이선스 검증용 공개키가 올바르지 않습니다."
        case .expired:
            return "오프라인 라이선스가 만료되었습니다."
        case .bundleMismatch(let expected, let actual):
            return "라이선스 번들 ID가 일치하지 않습니다. (요청: \(expected), 라이선스: \(actual))"
        case .fileNotFound(let path):
            return "오프라인 라이선스 파일을 찾을 수 없습니다: \(path)"
        case .unsupportedPlatform:
            return "현재 플랫폼에서는 라이선스 서명 검증을 지원하지 않습니다."
        }
    }
}

/// JSON+EdDSA 서명 파일을 검증하는 오프라인 라이선스 검증기.
public struct OfflineLicenseValidator: Sendable {
    /// 번들 내장 기본 공개키 (Ed25519 공개키 32바이트의 base64URL 인코딩).
    /// 필요 시 Info.plist의 "OfflineLicensePublicKey" 또는 환경변수 "GUJO_OFFLINE_LICENSE_PUBLIC_KEY"로 오버라이드 가능.
    public static let bundledPublicKey: String = "4G15nZq5O1o7r9xV3kX9s5hM1bA4aZ7yL2vR8eW0mN8"

    public let publicKey: String
    public let now: @Sendable () -> Date

    public init(
        publicKey: String? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        if let publicKey, !publicKey.isEmpty {
            self.publicKey = publicKey
        } else if let env = ProcessInfo.processInfo.environment["GUJO_OFFLINE_LICENSE_PUBLIC_KEY"], !env.isEmpty {
            self.publicKey = env
        } else if let plistKey = Bundle.main.object(forInfoDictionaryKey: "OfflineLicensePublicKey") as? String, !plistKey.isEmpty {
            self.publicKey = plistKey
        } else {
            self.publicKey = Self.bundledPublicKey
        }
        self.now = now
    }

    /// 파일 URL에서 라이선스 파일을 읽고 검증.
    public func validate(fileURL: URL, expectedBundleId: String? = nil) throws -> OfflineLicenseFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw OfflineLicenseError.fileNotFound(fileURL.path)
        }
        let data = try Data(contentsOf: fileURL)
        return try validate(data: data, expectedBundleId: expectedBundleId)
    }

    /// JSON 문자열 검증.
    public func validate(jsonString: String, expectedBundleId: String? = nil) throws -> OfflineLicenseFile {
        guard let data = jsonString.data(using: .utf8) else {
            throw OfflineLicenseError.invalidFormat("UTF-8 인코딩 실패")
        }
        return try validate(data: data, expectedBundleId: expectedBundleId)
    }

    /// 바이너리 JSON 데이터 검증.
    public func validate(data: Data, expectedBundleId: String? = nil) throws -> OfflineLicenseFile {
        #if canImport(CryptoKit)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let license: OfflineLicenseFile
        do {
            license = try decoder.decode(OfflineLicenseFile.self, from: data)
        } catch {
            throw OfflineLicenseError.invalidFormat(error.localizedDescription)
        }

        guard !license.bundleId.isEmpty else {
            throw OfflineLicenseError.invalidFormat("bundleId가 누락되었습니다.")
        }
        guard !license.signature.isEmpty else {
            throw OfflineLicenseError.invalidFormat("signature가 누락되었습니다.")
        }

        if let expected = expectedBundleId, !expected.isEmpty, license.bundleId != expected {
            throw OfflineLicenseError.bundleMismatch(expected: expected, actual: license.bundleId)
        }

        // 만료 검사
        if let exp = license.expiresAt, exp <= now() {
            throw OfflineLicenseError.expired
        }

        // 공개키 검증
        guard let pubData = Data(base64URLOrStandard: publicKey),
              let pubKey = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData) else {
            throw OfflineLicenseError.invalidPublicKey
        }

        guard let sigData = Data(base64URLOrStandard: license.signature) else {
            throw OfflineLicenseError.invalidSignature
        }

        // EdDSA 서명 확인:
        // 1) canonical payloadData 서명 확인
        // 2) 혹은 raw JSON payload ("payload": {...})에 대한 서명 확인 (상호호환)
        let validCanonical = pubKey.isValidSignature(sigData, for: license.payloadData)
        if validCanonical {
            return license
        }

        // sl1 payload 호환 검증:
        do {
            if let rawJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let payloadObj = rawJson["payload"] {
                let payloadBytes = try JSONSerialization.data(withJSONObject: payloadObj, options: [.sortedKeys])
                if pubKey.isValidSignature(sigData, for: payloadBytes) {
                    return license
                }
            }
        } catch {
            _ = error
        }

        throw OfflineLicenseError.invalidSignature
        #else
        throw OfflineLicenseError.unsupportedPlatform
        #endif
    }

    // MARK: - 발급 헬퍼 (로컬 테스트 및 관리용 Seam)

    #if canImport(CryptoKit)
    /// Ed25519 개인키/공개키 쌍 생성.
    public static func generateKeyPair() -> (privateKey: String, publicKey: String) {
        let priv = Curve25519.Signing.PrivateKey()
        let privStr = priv.rawRepresentation.base64URLEncodedString()
        let pubStr = priv.publicKey.rawRepresentation.base64URLEncodedString()
        return (privStr, pubStr)
    }

    /// 오프라인 라이선스 파일 생성 및 서명.
    public static func sign(
        bundleId: String,
        plan: String = "standard",
        customer: String? = nil,
        issuedAt: Date = Date(),
        expiresAt: Date? = nil,
        customClaims: [String: String]? = nil,
        privateKey: String
    ) throws -> (file: OfflineLicenseFile, json: String) {
        guard let privData = Data(base64URLOrStandard: privateKey),
              let priv = try? Curve25519.Signing.PrivateKey(rawRepresentation: privData) else {
            throw OfflineLicenseError.invalidPublicKey
        }

        var draft = OfflineLicenseFile(
            bundleId: bundleId,
            plan: plan,
            customer: customer,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            signature: "",
            customClaims: customClaims
        )
        let sig = try priv.signature(for: draft.payloadData)
        draft.signature = sig.base64URLEncodedString()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(draft)
        let jsonStr = String(data: encoded, encoding: .utf8) ?? ""
        return (draft, jsonStr)
    }
    #endif
}

// MARK: - Data Base64/Base64URL Extension

public extension Data {
    public init?(base64URLOrStandard value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // standard base64 먼저 시도
        if let d = Data(base64Encoded: trimmed) {
            self = d
            return
        }

        // base64url 시도
        var base64 = trimmed.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64.append(String(repeating: "=", count: (4 - base64.count % 4) % 4))
        if let d = Data(base64Encoded: base64) {
            self = d
            return
        }
        return nil
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
