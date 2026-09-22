import Foundation

/// 파일을 올려 **공유 링크**를 얻을 저장소. 사용자가 자기 것을 적어 넣는다.
///
/// 우리 서버를 쓰지 않는 이유는 그게 곧 저장 비용·보관 정책·약관이 되기 때문이다.
/// S3 API 를 말하는 곳이면 어디든 된다 — AWS S3 · Cloudflare R2 · Backblaze B2 ·
/// MinIO · Garage. 자격증명은 여기 담지 않는다(→ `credentialProfile`).
public struct ShareTarget: Codable, Equatable, Sendable {

    /// 저장소 엔드포인트. 예: `https://s3.example.com`, `https://s3.us-west-2.amazonaws.com`
    public var endpoint: String
    public var bucket: String
    /// SigV4 서명에 쓰는 리전. 지역 개념이 없는 구현도 값은 필요하다(보통 `us-east-1`).
    public var region: String

    /// 올린 뒤 사람에게 줄 주소의 앞부분. 예: `https://cdn.example.com`
    ///
    /// 비워 두면 엔드포인트로 만든 주소를 쓴다. CDN·커스텀 도메인을 앞에 두는 구성이
    /// 흔해서 따로 받는다 — 버킷 주소를 그대로 주면 캐시도 안 타고 주소가 길다.
    public var publicBaseURL: String

    /// 오브젝트 키 앞에 붙일 경로. 예: `screenshots`
    public var pathPrefix: String

    /// **path-style** 주소를 쓸지(`endpoint/bucket/key`).
    ///
    /// 끄면 virtual-host 방식(`bucket.endpoint/key`)이다. MinIO·Garage 같은 자체 호스팅은
    /// 보통 path-style 이라야 하고, AWS 는 둘 다 된다. 틀리면 404 나 서명 오류가 나는데
    /// 원인이 안 보여서 기본을 path-style 로 둔다(자체 호스팅에서 더 자주 맞다).
    public var usesPathStyle: Bool

    /// 자격증명 카드 이름. 실제 키는 카드(키체인)에 있고 여기엔 **이름만** 둔다.
    public var credentialProfile: String

    /// 링크를 몇 초 뒤에 만료시킬지. `nil` 이면 만료 없는 **공개 읽기** 주소다.
    ///
    /// 공개 읽기는 버킷을 열어 둬야 해서 운영 정책이 걸린다. 열 수 없는 환경에서는
    /// 서명된 만료 링크를 쓴다 — 버킷은 닫아 두고 링크 자체에 권한이 실린다.
    /// 대신 그 링크는 시간이 지나면 죽으므로, 문서에 박아 두면 나중에 깨진다.
    public var linkExpirySeconds: Int?

    public init(
        endpoint: String = "",
        bucket: String = "",
        region: String = "us-east-1",
        publicBaseURL: String = "",
        pathPrefix: String = "",
        usesPathStyle: Bool = true,
        credentialProfile: String = ShareCredential.defaultProfile,
        linkExpirySeconds: Int? = nil
    ) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.publicBaseURL = publicBaseURL
        self.pathPrefix = pathPrefix
        self.usesPathStyle = usesPathStyle
        self.credentialProfile = credentialProfile
        self.linkExpirySeconds = linkExpirySeconds
    }

    /// 올릴 준비가 됐는가. 하나라도 빠지면 무엇이 빠졌는지 알려준다.
    public var missingFields: [ShareTargetField] {
        var missing: [ShareTargetField] = []
        if Self.normalized(endpoint).isEmpty { missing.append(.endpoint) }
        if bucket.trimmingCharacters(in: .whitespaces).isEmpty { missing.append(.bucket) }
        if region.trimmingCharacters(in: .whitespaces).isEmpty { missing.append(.region) }
        if credentialProfile.trimmingCharacters(in: .whitespaces).isEmpty {
            missing.append(.credentialProfile)
        }
        return missing
    }

    public var isConfigured: Bool { missingFields.isEmpty }

    /// 앞뒤 공백과 끝 슬래시를 떼어 낸 값 — 사용자는 주소를 복사해 붙이므로
    /// `https://s3.example.com/` 처럼 끝에 슬래시가 붙어 오는 게 보통이다.
    static func normalized(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }
}

/// 설정 화면이 "무엇이 비었는지" 를 짚어 줄 수 있게 하는 식별자.
public enum ShareTargetField: String, Codable, CaseIterable, Sendable {
    case endpoint
    case bucket
    case region
    case credentialProfile
}
