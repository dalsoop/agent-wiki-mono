import Foundation

/// 제안된 사용자 후속 조치
public enum LibraryAccessSuggestedAction: String, Equatable, Sendable {
    case signIn
    case retry
    case updateApp
    case none
}

/// 라이브러리 접근 실패 원인. 손님에게 보이는 문구에는 엔지니어링 내부 용어(Agent Vault, grant, entitlement 등)를 절대로 노출하지 않는다.
/// 진단용 원문은 `diagnosticDescription` 에만 담는다.
public enum LibraryAccessFailure: Error, Equatable, Sendable {
    case unauthenticated
    case networkUnreachable
    case serverUnavailable(statusCode: Int)
    case rateLimited
    case clientOutdated(minVersion: String)
    case unknown(message: String)

    // MARK: - 하위 호환 편의 프로퍼티 및 생성자
    public static var noCredential: LibraryAccessFailure { .unauthenticated }
    public static var credentialExpired: LibraryAccessFailure { .unauthenticated }
    public static func network(_ error: URLError) -> LibraryAccessFailure { .networkUnreachable }
    public static func server(status: Int) -> LibraryAccessFailure { .serverUnavailable(statusCode: status) }
    public static func unknown(_ detail: String) -> LibraryAccessFailure { .unknown(message: detail) }

    // MARK: - 내부 용어 차단 필터
    /// 손님 화면 노출이 엄격히 금지된 엔지니어링 내부 용어 목록 (disciplines.md 26, 28행)
    public static let forbiddenInternalJargon: [String] = [
        "agent vault",
        "agent-vault",
        "agentvault",
        "vault",
        "grant",
        "grants",
        "entitlement",
        "entitlements",
        "bearer",
        "apikey",
        "api key",
        "session probe",
        "deviceidentity",
        "grpc",
        "reapi",
    ]

    /// 문자열에 내부 용어가 포함되어 있는지 검사
    public static func containsInternalJargon(_ text: String) -> Bool {
        let lower = text.lowercased()
        return forbiddenInternalJargon.contains { lower.contains($0) }
    }

    /// 내부 용어를 제거하고 손님 친화적인 기본 문구로 안전하게 치환
    public static func sanitize(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "일시적인 오류가 발생했습니다. 잠시 후 다시 시도해 주세요."
        }
        if containsInternalJargon(trimmed) {
            return "라이브러리 서비스 접근 중 문제가 발생했습니다. 잠시 후 다시 시도해 주세요."
        }
        return trimmed
    }

    /// 임의의 Error로부터 LibraryAccessFailure로 변환
    public static func from(_ error: Error) -> LibraryAccessFailure {
        if let failure = error as? LibraryAccessFailure {
            return failure
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .networkUnreachable
        }
        let msg = error.localizedDescription
        let lower = msg.lowercased()

        if let statusFailure = matchKnownStatus(lower) {
            return statusFailure
        }
        if isNetworkIssue(lower) {
            return .networkUnreachable
        }
        return .unknown(message: sanitize(msg))
    }

    private static func matchKnownStatus(_ lower: String) -> LibraryAccessFailure? {
        let authKeywords = ["401", "unauthenticated", "unauthorized", "인증", "로그인"]
        if authKeywords.contains(where: { lower.contains($0) }) {
            return .unauthenticated
        }
        let rateKeywords = ["429", "rate limit", "한도"]
        if rateKeywords.contains(where: { lower.contains($0) }) {
            return .rateLimited
        }
        let outdatedKeywords = ["426", "upgrade required", "client outdated", "update required"]
        if outdatedKeywords.contains(where: { lower.contains($0) }) {
            return .clientOutdated(minVersion: "최신 버전")
        }
        if let serverCode = detectServerCode(lower) {
            return .serverUnavailable(statusCode: serverCode)
        }
        return nil
    }

    private static func detectServerCode(_ lower: String) -> Int? {
        let serverCodes = [500, 502, 503, 504]
        for code in serverCodes where lower.contains("\(code)") {
            return code
        }
        return nil
    }

    private static func isNetworkIssue(_ lower: String) -> Bool {
        let networkKeywords = ["network", "offline", "timed out", "인터넷", "연결 끊김"]
        return networkKeywords.contains(where: { lower.contains($0) })
    }

    // MARK: - 손님 화면용 속성 (내부 용어 노출 금지)
    public var userFacingTitle: String {
        switch self {
        case .unauthenticated:
            return "로그인이 필요합니다"
        case .networkUnreachable:
            return "인터넷에 연결되지 않았습니다"
        case .serverUnavailable:
            return "서버에 연결할 수 없습니다"
        case .rateLimited:
            return "요청 한도를 초과했습니다"
        case .clientOutdated:
            return "앱 업데이트가 필요합니다"
        case .unknown:
            return "라이브러리를 불러올 수 없습니다"
        }
    }

    public var userFacingDescription: String {
        switch self {
        case .unauthenticated:
            return "로그인하면 구매한 앱이 여기에 나타납니다."
        case .networkUnreachable:
            return "인터넷 연결 상태를 확인한 뒤 다시 시도해 주세요."
        case .serverUnavailable(let statusCode):
            if statusCode > 0 {
                return "서버가 잠시 응답하지 않습니다. 잠시 후 다시 시도해 주세요. (HTTP \(statusCode))"
            }
            return "서버가 잠시 응답하지 않습니다. 잠시 후 다시 시도해 주세요."
        case .rateLimited:
            return "단시간에 너무 많은 요청이 발생했습니다. 잠시 후 다시 시도해 주세요."
        case .clientOutdated(let minVersion):
            return "원활한 서비스 이용을 위해 Gujo Cloud Apps \(minVersion) 이상으로 업데이트해 주세요."
        case .unknown(let message):
            return Self.sanitize(message)
        }
    }

    public var suggestedAction: LibraryAccessSuggestedAction {
        switch self {
        case .unauthenticated:
            return .signIn
        case .networkUnreachable, .serverUnavailable, .rateLimited, .unknown:
            return .retry
        case .clientOutdated:
            return .updateApp
        }
    }

    /// 내부 진단용. support report 에 첨부되며 손님 화면에는 노출하지 않는다.
    public var diagnosticDescription: String {
        switch self {
        case .unauthenticated:
            return "LibraryAccessFailure.unauthenticated: missing or invalid credentials"
        case .networkUnreachable:
            return "LibraryAccessFailure.networkUnreachable: network disconnected or host unreachable"
        case .serverUnavailable(let statusCode):
            return "LibraryAccessFailure.serverUnavailable: HTTP \(statusCode)"
        case .rateLimited:
            return "LibraryAccessFailure.rateLimited: request rate limit exceeded"
        case .clientOutdated(let minVersion):
            return "LibraryAccessFailure.clientOutdated: required minVersion=\(minVersion)"
        case .unknown(let message):
            return "LibraryAccessFailure.unknown: \(message)"
        }
    }
}

extension LibraryAccessFailure: LocalizedError {
    public var errorDescription: String? {
        userFacingDescription
    }
}
