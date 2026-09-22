import Foundation
import EndpointRouterKit

/// 호스트는 EndpointRouterKit 키만. 경로 상수는 여기 한곳.
public enum StoreOpsStaffEndpoints: Sendable {
    public static let prodHostKey = "software-prod"
    public static let localHostKey = "software"
    public static let skillPublishPath = "api/skills/publish"
    public static let skillDeprecatePath = "api/skills/deprecate"
    public static let downloadPipelinePath = "api/downloads/pipeline"

    /// `software-prod` 는 EndpointRouterKit 원장 어디에도 선언돼 있지 않다(2026-09-11 실측:
    /// 내장 `endpoints-defaults.json`·빌드 앱 원장·`GUJO_ENDPOINT_*` env 전부 없음).
    /// `EndpointRouter.string` 은 모르는 키에 예외 대신 `""` 를 돌려주므로, 그 값을 그대로 쓰면
    /// `URL(string: "")` 이 nil 이 되어 스태프 API 의 base 가 통째로 `file:///` 로 조용히 퇴화한다 —
    /// 스킬 발행·폐기·다운로드 감사 요청이 전부 파일시스템 루트를 향한다.
    /// 함대 공용 원장을 건드리는 대신 소비하는 이쪽에서 폴백 사슬을 둔다.
    /// `apps-prod`/`apps` 는 둘 다 apps.gujo 호스트 — 스태프 API 가 사는 곳이다.
    public static let prodHostFallbackKeys = ["apps-prod", "apps"]

    /// 키를 주소로 푼다. prod 키만 위 폴백 사슬을 탄다. 아무것도 못 풀면 `""`.
    public static func resolvedHost(_ hostKey: String) -> String {
        let direct = EndpointRouter.string(hostKey)
        if !direct.isEmpty { return direct }
        guard hostKey == prodHostKey else { return "" }
        for fallback in prodHostFallbackKeys {
            let resolved = EndpointRouter.string(fallback)
            if !resolved.isEmpty { return resolved }
        }
        return ""
    }

    public static func baseURL(hostKey: String = prodHostKey) -> URL {
        let raw = resolvedHost(hostKey)
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: "/")
    }

    public static func url(hostKey: String = prodHostKey, path: String) -> URL {
        baseURL(hostKey: hostKey).appendingPathComponent(path)
    }
}

public enum StoreOpsStaffError: Error, Equatable, LocalizedError {
    case http(Int)
    case decode(String)
    case missingToken
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .http(let code): return "HTTP \(code)"
        case .decode(let message): return "decode: \(message)"
        case .missingToken: return "staff token missing"
        case .transport(let message): return message
        }
    }
}
