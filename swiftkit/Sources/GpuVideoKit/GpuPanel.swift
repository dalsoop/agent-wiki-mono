import Foundation
import EndpointRouterKit

/// GPU 패널(FastAPI `gpu-panel`) 공용 엔드포인트 상수.
/// 두 앱(운영 콘솔 gpu-server-manager · 생성 스튜디오 gpu-video-studio)이
/// 같은 패널 백엔드를 가리키도록 정본을 한 곳에 둔다.
public enum GpuPanel {
    /// 기본 패널 베이스 URL — `EndpointRouterKit` 에 정본을 위임한다.
    @available(*, deprecated, message: "EndpointRouter.gpuPanel 을 쓴다")
    public static var defaultBaseURL: String { EndpointRouter.gpuPanel }

    /// 끝 슬래시를 걷고 공백을 다듬어 정규화한다.
    public static func normalize(_ baseURL: String) -> String {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// 평문 HTTP 인가 — 내부망(10.x)은 ATS 예외로 허용하지만, 공개 도메인을
    /// 평문으로 두면 basic 자격이 그대로 노출된다. 설정 UI 의 경고 판정에 쓴다.
    public static func isPlaintextPublic(_ baseURL: String) -> Bool {
        let s = normalize(baseURL).lowercased()
        guard s.hasPrefix("http://") else { return false }
        let host = s.dropFirst("http://".count).prefix { $0 != "/" && $0 != ":" }
        
        let isInternalIPOrLocal = ["10.", "192.168.", "127."].contains(where: { host.hasPrefix($0) })
        let conditions = [
            isInternalIPOrLocal,
            host == "localhost",
            host.hasSuffix(".internal.kr")
        ]
        
        return !conditions.contains(true)
    }
}

/// 패널 앞단(traefik)의 HTTP Basic 자격. 내부망 직결에는 필요 없고,
/// 공개 도메인(`video.ranode.net` 등)으로 붙을 때만 쓴다.
public struct PanelCredential: Sendable, Equatable {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    public var isEmpty: Bool { username.isEmpty && password.isEmpty }

    /// `Authorization` 헤더 값. UTF-8 base64 — traefik basicAuth 와 같은 규약.
    public var authorizationHeaderValue: String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }
}

/// baseURL 별 자격 조회 표면. 앱은 Keychain 구현을 주입하고, 테스트는 목을 준다.
/// 자격이 없으면 `nil` — 그때는 인증 헤더 없이(=내부망 그대로) 나간다.
public protocol PanelCredentialProviding: Sendable {
    func credential(for baseURL: String) -> PanelCredential?
}

/// 고정 자격 제공자 — 테스트·단발 호출용.
public struct StaticPanelCredentialProvider: PanelCredentialProviding {
    private let credential: PanelCredential?

    public init(_ credential: PanelCredential?) {
        self.credential = credential
    }

    public func credential(for baseURL: String) -> PanelCredential? {
        guard let c = credential, !c.isEmpty else { return nil }
        return c
    }
}
