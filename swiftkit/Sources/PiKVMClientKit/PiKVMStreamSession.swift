import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// kvmd 세션(`/api/ws`)을 열어 두는 것만 하는 객체.
///
/// **왜 필요한가** — kvmd 는 영상 스트리머(ustreamer)를 상주시키지 않는다(`streamer.forever: false`).
/// 보는 클라이언트가 생기면 켜고, 마지막 클라이언트가 떠나면 `shutdown_delay`(기본 10초) 뒤 끈다.
/// 그리고 **그 "클라이언트" 판정은 websocket 세션이 한다** — MJPEG 주소(`/streamer/stream`)를
/// 그냥 때리는 것으로는 안 켜진다. 스트리머가 꺼져 있으면 그 주소는 nginx 502 를 줄 뿐이다.
///
/// 실측(2026-08-10, PiKVM 4.121): ws 를 열자 4초 안에 `/api/streamer` 의 `streamer` 가
/// null → 객체로 바뀌었다. ws 없이 MJPEG 만 당겼을 때는 계속 502(157바이트 HTML)였다.
///
/// 그래서 영상을 보려면 **먼저 이 세션을 열고** MJPEG 를 읽어야 한다. 나중에 키보드·마우스
/// 이벤트를 보낼 때도 같은 세션을 쓴다.
public final class PiKVMStreamSession: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case connecting
        case open
        case failed(String)
    }

    private let lock = NSLock()
    private var _state: State = .idle
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private let trustedHost: String?
    private let onStateChange: (@Sendable (State) -> Void)?

    public var state: State { lock.withLock { _state } }

    /// - Parameter onStateChange: 상태 변화 통지. 임의 스레드에서 불린다.
    /// - Parameter wantsVideo: true 면 `stream=1` — **이게 스트리머를 켠다.**
    public init(
        client: PiKVMClient,
        wantsVideo: Bool = true,
        onStateChange: (@Sendable (State) -> Void)? = nil
    ) {
        self.trustedHost = client.endpoint.allowsUntrustedCertificate ? client.endpoint.host : nil
        self.onStateChange = onStateChange
        self.url = client.websocketURL(wantsVideo: wantsVideo)
        self.headers = client.credentials.headers
        super.init()
    }

    private let url: URL?
    private let headers: [String: String]

    private func set(_ newState: State) {
        let changed: Bool = lock.withLock {
            guard _state != newState else { return false }
            _state = newState
            return true
        }
        if changed { onStateChange?(newState) }
    }

    public func open() {
        close()
        guard let url else {
            set(.failed("websocket 주소를 만들 수 없다"))
            return
        }
        set(.connecting)

        var request = URLRequest(url: url)
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }

        let configuration = URLSessionConfiguration.ephemeral
        // 세션은 계속 열려 있어야 한다 — 리소스 타임아웃을 걸면 보는 도중 스트리머가 꺼진다.
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = TimeInterval.infinity
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: request)
        lock.withLock {
            self.session = session
            self.task = task
        }
        task.resume()
        receiveLoop(task)
    }

    public func close() {
        let (oldTask, oldSession): (URLSessionWebSocketTask?, URLSession?) = lock.withLock {
            defer {
                task = nil
                session = nil
            }
            return (task, session)
        }
        oldTask?.cancel(with: .goingAway, reason: nil)
        oldSession?.invalidateAndCancel()
        set(.idle)
    }

    /// kvmd 가 보내는 상태 이벤트를 계속 받는다. **읽지 않으면 세션이 죽는다** —
    /// URLSession 은 receive 를 걸어 두지 않으면 들어온 메시지를 쌓아만 두고,
    /// 서버는 응답 없는 클라이언트를 정리한다.
    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                // 내용은 지금 쓰지 않는다(영상 기동이 목적). 다음 메시지를 계속 받는다.
                self.receiveLoop(task)
            case let .failure(error):
                let cancelled = (error as NSError).code == NSURLErrorCancelled
                if !cancelled { self.set(.failed(error.localizedDescription)) }
            }
        }
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol proto: String?
    ) {
        set(.open)
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        set(.idle)
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
