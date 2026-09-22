import Foundation
import CryptoKit

/// AWS Signature Version 4 서명 원시체 — S3/Garage(Route53 등 다른 AWS 서비스도) 클라이언트가 공유.
///
/// 이 모듈이 있기 전 서명 로직이 두 곳에서 손으로 굴렸다:
/// - `swift-app-publish-kit` 의 `S3Publisher`(비동기 URLSession)
/// - `agent-wiki-kit` 의 `GujoBlobSync`(동기 URLSession + DispatchSemaphore)
///
/// 둘 다 같은 알고리즘(같은 canonical request 구조, 같은 HMAC 체인) 이라 한 곳으로 모은다.
/// 외부 셸(rclone/aws CLI)/AWS SDK 없이 CryptoKit 만으로 서명한다. 전송·객체 래퍼는 각 클라이언트가
/// 소유한다 — 이 타입은 **서명만** 계산한다(pure function).
///
/// 검증: AWS 가 공개하는 sig-v4-test-suite `get-vanilla` 벡터로 출력을 고정한다(아래 테스트).
public struct SigV4Signer: Sendable {
    public let accessKey: String
    public let secretKey: String
    public let region: String
    public let service: String

    /// - Parameters:
    ///   - service: 기본 `s3`. Route53 은 `route53`, 등.
    public init(accessKey: String, secretKey: String, region: String, service: String = "s3") {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.region = region
        self.service = service
    }

    /// AWS SigV4 `Authorization` 헤더값을 계산한다.
    ///
    /// 호출자가 서명에 포함할 헤더를 제공한다(S3 는 보통 host·x-amz-content-sha256·x-amz-date).
    /// `canonicalUri`·`canonicalQueryString` 은 이미 정규화된 값 — `canonicalQuery(_:)` 로 조립.
    ///
    /// - Parameters:
    ///   - method: HTTP 메서드.
    ///   - canonicalUri: 인코딩된 경로(예 `/bucket/key`). 버킷 자체은 `/bucket`.
    ///   - canonicalQueryString: 정규화 쿼리. 빈 문자열 허용.
    ///   - headers: 서명에 넣을 (이름, 값). 이름은 소문자 권장. 정렬은 내부에서 한다.
    ///   - payloadHash: 페이로드 sha256 hex. 본문 없는 요청은 `emptyPayloadHash`.
    ///   - amzDate: `yyyyMMdd'T'HHmmss'Z'`.
    ///   - dateStamp: `yyyyMMdd`.
    /// - Returns: `AWS4-HMAC-SHA256 Credential=…, SignedHeaders=…, Signature=…`
    public func authorization(
        method: String,
        canonicalUri: String,
        canonicalQueryString: String,
        headers: [(name: String, value: String)],
        payloadHash: String,
        amzDate: String,
        dateStamp: String
    ) -> String {
        let sorted = headers.sorted { $0.name < $1.name }
        // canonical headers: 각 줄 "name:value\n" — 블록 전체가 \n 으로 끝난다.
        let canonicalHeaders = sorted.map { "\($0.name):\($0.value)\n" }.joined()
        let signedHeaders = sorted.map { $0.name }.joined(separator: ";")
        let canonicalRequest = "\(method)\n\(canonicalUri)\n\(canonicalQueryString)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(scope)\n" + Self.sha256Hex(Data(canonicalRequest.utf8))
        let signature = Self.signature(secretKey: secretKey, region: region, service: service, dateStamp: dateStamp, stringToSign: stringToSign)
        return "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    /// 빈 페이로드의 sha256 — GET/DELETE/HEAD 같은 본문 없는 요청에 쓴다.
    public static let emptyPayloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    /// 정규화 쿼리 — 키 정렬(동명키는 값으로 타이브레이크) + unreserved 퍼센트 인코딩.
    /// 빈 입력은 빈 문자열.
    public static func canonicalQuery(_ query: [(String, String)]) -> String {
        guard !query.isEmpty else { return "" }
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s }
        var encoded: [(String, String)] = []
        for (name, value) in query { encoded.append((enc(name), enc(value))) }
        encoded.sort { lhs, rhs in lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0 }
        var parts: [String] = []
        for (name, value) in encoded { parts.append(name + "=" + value) }
        return parts.joined(separator: "&")
    }

    /// SHA-256 hex.
    public static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).hex
    }

    /// 서명 키 체인: AWS4+secret → dateStamp → region → service → "aws4_request" → HMAC(stringToSign).
    static func signature(secretKey: String, region: String, service: String, dateStamp: String, stringToSign: String) -> String {
        let k1 = hmac(key: Data(("AWS4" + secretKey).utf8), message: dateStamp)
        let k2 = hmac(key: k1, message: region)
        let k3 = hmac(key: k2, message: service)
        let k4 = hmac(key: k3, message: "aws4_request")
        return hmac(key: k4, message: stringToSign).hex
    }

    static func hmac(key: Data, message: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key)))
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
