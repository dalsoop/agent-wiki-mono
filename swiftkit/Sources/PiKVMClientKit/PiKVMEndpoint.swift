import Foundation
import HTTPClientKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// PiKVM(kvmd) 한 대를 가리키는 접속 지점.
///
/// 이 장비는 공장 출하 상태에서 **자체 서명 인증서**를 쓴다(내부망 고정 IP 라 CA 발급이 없다).
/// 그래서 신뢰 예외를 `allowsUntrustedCertificate` 로 **장비마다 명시적으로** 켠다 —
/// 전역 ATS 예외나 URLSession 전역 델리게이트로 열지 않는다(다른 앱·다른 호스트까지 열린다).
public struct PiKVMEndpoint: Sendable, Codable, Equatable {
    public var host: String
    /// nil 이면 스킴 기본 포트(https 443 / http 80).
    public var port: Int?
    public var useTLS: Bool
    /// 자체 서명 인증서 허용. 켠 장비의 호스트에만 적용된다.
    public var allowsUntrustedCertificate: Bool

    public init(
        host: String,
        port: Int? = nil,
        useTLS: Bool = true,
        allowsUntrustedCertificate: Bool = true
    ) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.allowsUntrustedCertificate = allowsUntrustedCertificate
    }

    public var baseURL: URL {
        var c = URLComponents()
        c.scheme = useTLS ? "https" : "http"
        c.host = host
        c.port = port
        // 호스트만으로 URLComponents 를 만들면 path 가 비어 상대 경로 결합이 어긋난다.
        c.path = ""
        return c.url ?? URL(string: "\(useTLS ? "https" : "http")://\(host)")!
    }

    /// `/api/atx` 같은 절대 경로 + 질의 문자열로 최종 URL 을 만든다.
    public func url(path: String, query: [String: String] = [:]) -> URL? {
        var c = URLComponents()
        c.scheme = useTLS ? "https" : "http"
        c.host = host
        c.port = port
        c.path = path.hasPrefix("/") ? path : "/" + path
        if !query.isEmpty {
            c.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return c.url
    }
}

/// kvmd 인증 자격증명. 헤더 인증(`X-KVMD-User`/`X-KVMD-Passwd`)을 쓴다 —
/// 쿠키 세션(`/api/auth/login`)과 달리 무상태라 CLI 단발 호출에 맞는다.
public struct PiKVMCredentials: Sendable, Equatable {
    public var user: String
    public var passwd: String

    public init(user: String, passwd: String) {
        self.user = user
        self.passwd = passwd
    }

    public var headers: [String: String] {
        ["X-KVMD-User": user, "X-KVMD-Passwd": passwd]
    }
}

/// 자체 서명 인증서를 **지정한 호스트에 한해** 신뢰하는 URLSession 전송.
///
/// `HTTPClientKit.HTTPClient` 를 구현한다 — generic 인 것은 전송 계약뿐이고,
/// PiKVM 고유 사정(자체 서명·헤더 인증)은 이 Kit 안에 갇힌다.
public final class PiKVMTransport: NSObject, HTTPClient, URLSessionDelegate, @unchecked Sendable {
    private let trustedHost: String?
    private let timeout: TimeInterval
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
    }()

    /// - Parameter trustedSelfSignedHost: 이 호스트의 자체 서명 인증서만 신뢰한다. nil 이면 표준 검증.
    public init(trustedSelfSignedHost: String?, timeout: TimeInterval = 10) {
        self.trustedHost = trustedSelfSignedHost
        self.timeout = timeout
        super.init()
    }

    public func send(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data?
    ) async throws -> (status: Int, data: Data) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    /// 파일을 **메모리에 올리지 않고** 본문으로 보낸다.
    /// ISO 는 기가바이트 단위라 `Data(contentsOf:)` 로 읽으면 앱이 그대로 죽는다.
    public func upload(
        file: URL,
        to url: URL,
        headers: [String: String],
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> (status: Int, data: Data) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        // 업로드는 요청 타임아웃(기본 10초)에 걸리면 안 된다 — 큰 이미지는 수십 분이다.
        req.timeoutInterval = 3600

        // 완료 핸들러형 업로드 태스크는 응답 본문을 모아 주면서도 델리게이트의 TLS 신뢰 예외를 그대로 탄다.
        nonisolated(unsafe) var token: NSKeyValueObservation?
        defer { token?.invalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: req, fromFile: file) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: (status, data ?? Data()))
            }
            if let progress {
                token = task.progress.observe(\.fractionCompleted) { p, _ in
                    progress(p.fractionCompleted)
                }
            }
            task.resume()
        }
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let host = trustedHost,
            challenge.protectionSpace.host == host,
            let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
