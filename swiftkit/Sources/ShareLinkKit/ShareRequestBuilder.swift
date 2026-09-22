import Foundation
import SigV4Kit

/// 업로드 요청과 공유 주소를 **만들기만** 하는 계층. 네트워크를 타지 않아 전부 테스트된다.
///
/// S3 호환 저장소에서 틀리기 쉬운 곳이 여기 다 모여 있다 — path-style 과 virtual-host
/// 주소가 다르고, 서명에 쓰는 canonical URI 는 키를 세그먼트 단위로 인코딩해야 하며,
/// `x-amz-content-sha256` 이 없으면 통째로 거부된다. 실패하면 403 만 오고 이유는 안 온다.
public enum ShareRequestBuilder {

    public enum BuildError: Error, LocalizedError, Equatable {
        case incompleteTarget([ShareTargetField])
        case invalidEndpoint(String)

        public var errorDescription: String? {
            switch self {
            case .incompleteTarget(let fields):
                return "공유 저장소 설정이 덜 됐다: \(fields.map(\.rawValue).joined(separator: ", "))"
            case .invalidEndpoint(let value):
                return "엔드포인트 주소를 읽을 수 없다: \(value)"
            }
        }
    }

    /// 오브젝트를 올릴 주소(서명 대상).
    public static func uploadURL(target: ShareTarget, objectKey: String) throws -> URL {
        guard target.isConfigured else {
            throw BuildError.incompleteTarget(target.missingFields)
        }
        let endpoint = ShareTarget.normalized(target.endpoint)
        guard var components = URLComponents(string: endpoint), components.host != nil else {
            throw BuildError.invalidEndpoint(target.endpoint)
        }
        let bucket = target.bucket.trimmingCharacters(in: .whitespaces)
        if target.usesPathStyle {
            components.path = "/\(bucket)/\(objectKey)"
        } else {
            components.host = "\(bucket).\(components.host ?? "")"
            components.path = "/\(objectKey)"
        }
        // URLComponents 는 path 를 알아서 인코딩하지만, 서명은 우리가 만든 문자열과
        // **정확히 같아야** 하므로 canonicalURI 를 따로 계산해 쓴다.
        guard let url = components.url else { throw BuildError.invalidEndpoint(target.endpoint) }
        return url
    }

    /// 서명에 쓰는 canonical URI — 세그먼트마다 인코딩하되 구분자 `/` 는 남긴다.
    public static func canonicalURI(target: ShareTarget, objectKey: String) -> String {
        let bucket = target.bucket.trimmingCharacters(in: .whitespaces)
        let path = target.usesPathStyle ? "\(bucket)/\(objectKey)" : objectKey
        let encoded = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { encodeSegment(String($0)) }
            .joined(separator: "/")
        return "/" + encoded
    }

    /// 사람에게 줄 주소.
    ///
    /// `publicBaseURL` 이 있으면 그걸 쓴다 — CDN·커스텀 도메인을 앞에 두는 구성이 흔하고,
    /// 버킷 주소를 그대로 주면 캐시도 안 타고 주소가 길다.
    public static func publicURL(target: ShareTarget, objectKey: String) throws -> URL {
        let base = ShareTarget.normalized(target.publicBaseURL)
        if !base.isEmpty {
            guard let url = URL(string: "\(base)/\(objectKey)") else {
                throw BuildError.invalidEndpoint(target.publicBaseURL)
            }
            return url
        }
        return try uploadURL(target: target, objectKey: objectKey)
    }

    /// **서명된 만료 링크**(presigned GET).
    ///
    /// 버킷을 공개로 열 수 없을 때 쓴다 — 권한이 링크 자체에 실린다. 대신 만료되므로
    /// 문서에 박아 두면 나중에 깨진다. 그래서 기본은 공개 읽기고 이건 선택이다.
    ///
    /// 공개 주소와 달리 `publicBaseURL` 을 쓸 수 없다. 서명은 **호스트와 경로에 묶여**
    /// 있어서, 앞단 도메인을 갈아 끼우면 서명이 안 맞는다.
    public static func presignedURL(
        target: ShareTarget,
        objectKey: String,
        accessKey: String,
        secretKey: String,
        date: Date,
        expiresIn seconds: Int
    ) throws -> URL {
        let url = try uploadURL(target: target, objectKey: objectKey)
        guard let host = url.host, var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw BuildError.invalidEndpoint(target.endpoint) }

        let region = target.region.trimmingCharacters(in: .whitespaces)
        let amzDate = Self.amzDate(date)
        let dateStamp = String(amzDate.prefix(8))
        let scope = "\(dateStamp)/\(region)/s3/aws4_request"
        // S3 가 허용하는 만료는 최대 7일이다. 넘겨 주면 요청 자체가 거절된다.
        let expiry = min(max(1, seconds), 604_800)

        let query: [(String, String)] = [
            ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
            ("X-Amz-Credential", "\(accessKey)/\(scope)"),
            ("X-Amz-Date", amzDate),
            ("X-Amz-Expires", String(expiry)),
            ("X-Amz-SignedHeaders", "host"),
        ]
        let canonicalQueryString = SigV4Signer.canonicalQuery(query)

        let signer = SigV4Signer(
            accessKey: accessKey, secretKey: secretKey, region: region, service: "s3"
        )
        // presigned 는 본문이 없다 — 대신 규격이 정한 문자열을 페이로드 해시 자리에 넣는다.
        let authorization = signer.authorization(
            method: "GET",
            canonicalUri: canonicalURI(target: target, objectKey: objectKey),
            canonicalQueryString: canonicalQueryString,
            headers: [("host", hostHeader(host: host, port: url.port))],
            payloadHash: "UNSIGNED-PAYLOAD",
            amzDate: amzDate,
            dateStamp: dateStamp
        )
        guard let signature = authorization.components(separatedBy: "Signature=").last else {
            throw BuildError.invalidEndpoint(target.endpoint)
        }

        components.percentEncodedQuery = canonicalQueryString + "&X-Amz-Signature=" + signature
        guard let signed = components.url else {
            throw BuildError.invalidEndpoint(target.endpoint)
        }
        return signed
    }

    /// 설정에 따라 공개 주소 또는 만료 링크를 돌려준다.
    public static func shareURL(
        target: ShareTarget,
        objectKey: String,
        accessKey: String,
        secretKey: String,
        date: Date
    ) throws -> URL {
        guard let expiry = target.linkExpirySeconds, expiry > 0 else {
            return try publicURL(target: target, objectKey: objectKey)
        }
        return try presignedURL(
            target: target, objectKey: objectKey, accessKey: accessKey,
            secretKey: secretKey, date: date, expiresIn: expiry
        )
    }

    /// 서명까지 끝난 PUT 요청.
    public static func uploadRequest(
        target: ShareTarget,
        objectKey: String,
        body: Data,
        contentType: String,
        accessKey: String,
        secretKey: String,
        date: Date,
        cacheSeconds: Int? = nil
    ) throws -> URLRequest {
        let url = try uploadURL(target: target, objectKey: objectKey)
        guard let host = url.host else { throw BuildError.invalidEndpoint(target.endpoint) }

        let payloadHash = SigV4Signer.sha256Hex(body)
        let amzDate = Self.amzDate(date)
        let dateStamp = String(amzDate.prefix(8))

        var headers: [(name: String, value: String)] = [
            ("host", hostHeader(host: host, port: url.port)),
            ("x-amz-content-sha256", payloadHash),
            ("x-amz-date", amzDate),
            ("content-type", contentType),
        ]
        if let cacheSeconds {
            headers.append(("cache-control", "public, max-age=\(cacheSeconds)"))
        }

        let signer = SigV4Signer(
            accessKey: accessKey, secretKey: secretKey,
            region: target.region.trimmingCharacters(in: .whitespaces), service: "s3"
        )
        let authorization = signer.authorization(
            method: "PUT",
            canonicalUri: canonicalURI(target: target, objectKey: objectKey),
            canonicalQueryString: "",
            headers: headers,
            payloadHash: payloadHash,
            amzDate: amzDate,
            dateStamp: dateStamp
        )

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = body
        for header in headers where header.name != "host" {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        return request
    }

    /// 기본 포트면 붙이지 않는다 — 붙이면 서명과 실제 요청의 host 가 달라져 403 이 난다.
    static func hostHeader(host: String, port: Int?) -> String {
        guard let port, port != 80, port != 443 else { return host }
        return "\(host):\(port)"
    }

    /// `yyyyMMdd'T'HHmmss'Z'` (UTC).
    public static func amzDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    /// S3 가 요구하는 인코딩 — unreserved 를 뺀 전부를 퍼센트 인코딩한다.
    /// `URLComponents` 의 기본 규칙과 다르므로 직접 만든다(다르면 서명이 안 맞는다).
    static func encodeSegment(_ segment: String) -> String {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        return segment.addingPercentEncoding(withAllowedCharacters: unreserved) ?? segment
    }
}
