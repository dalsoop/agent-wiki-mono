import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// PiKVM 실시간 화면(MJPEG)을 프레임 단위로 흘려 준다.
///
/// **AppKit 을 쓰지 않는다** — GUI 뷰어와 헤드리스 CLI 가 같은 코드로 받게 하려는 것이다.
/// 디코드·표시는 소비자가 한다. 그래서 "GUI 에서만 되는 것" 이 생기지 않고, 실장비 검증도
/// 터미널에서 그대로 된다.
///
/// 세 가지를 여기서 책임진다:
/// 1. **kvmd 세션을 먼저 연다.** 안 그러면 PiKVM 이 스트리머를 켜지 않는다(`forever: false`).
/// 2. **기동을 기다린다.** 세션을 열어도 몇 초 걸리고 그동안 nginx 는 502 를 준다 —
///    실패가 아니라 재시도 대상이다.
/// 3. **프레임 경계를 푼다.** `MJPEGFrameSplitter`(SOI/EOI 스캔).
public final class PiKVMVideoStream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    public enum Event: Sendable {
        case connecting(attempt: Int)
        /// JPEG 한 장.
        case frame(Data)
        case failed(String)
    }

    private let client: PiKVMClient
    private let handler: @Sendable (Event) -> Void
    private let startupGraceSeconds: Int

    private let lock = NSLock()
    private var splitter = MJPEGFrameSplitter()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var kvmdSession: PiKVMStreamSession?
    private var attempt = 0
    private var stopped = false

    /// - Parameters:
    ///   - startupGraceSeconds: 스트리머 기동을 기다리는 최대 초. 실측 4초 안팎이라 넉넉히 잡는다.
    ///   - handler: 임의 스레드에서 불린다.
    public init(
        client: PiKVMClient,
        startupGraceSeconds: Int = 20,
        handler: @escaping @Sendable (Event) -> Void
    ) {
        self.client = client
        self.handler = handler
        self.startupGraceSeconds = startupGraceSeconds
        super.init()
    }

    public func start() {
        lock.withLock {
            stopped = false
            attempt = 0
            splitter.reset()
        }
        // kvmd 세션이 곧 "보는 사람" 이다. 이게 없으면 아래 연결은 영원히 502 다.
        let kvmd = PiKVMStreamSession(client: client)
        lock.withLock { kvmdSession = kvmd }
        kvmd.open()
        connect()
    }

    public func stop() {
        let (oldTask, oldSession, oldKVMD): (URLSessionDataTask?, URLSession?, PiKVMStreamSession?) =
            lock.withLock {
                stopped = true
                defer {
                    task = nil
                    session = nil
                    kvmdSession = nil
                }
                return (task, session, kvmdSession)
            }
        oldTask?.cancel()
        oldSession?.invalidateAndCancel()
        oldKVMD?.close()
    }

    private func connect() {
        guard let url = client.streamURL else {
            handler(.failed("스트림 주소를 만들 수 없다"))
            return
        }
        let currentAttempt: Int = lock.withLock {
            attempt += 1
            return attempt
        }
        handler(.connecting(attempt: currentAttempt))

        var request = URLRequest(url: url)
        for (key, value) in client.credentials.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 15

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        // 스트림은 끝나지 않는다 — 리소스 타임아웃을 걸면 보는 도중 끊긴다.
        configuration.timeoutIntervalForResource = TimeInterval.infinity
        let urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let dataTask = urlSession.dataTask(with: request)
        lock.withLock {
            session = urlSession
            task = dataTask
        }
        dataTask.resume()
    }

    /// 스트리머가 아직 안 떴을 때. 실패로 끝내지 않고 1초 뒤 다시 붙는다.
    private func retryAfterStartupDelay() {
        let (shouldRetry, currentAttempt): (Bool, Int) = lock.withLock {
            (!stopped && attempt < startupGraceSeconds, attempt)
        }
        guard shouldRetry else {
            if !lock.withLock({ stopped }) {
                handler(.failed("스트리머 기동 대기 시간 초과 — PiKVM 에서 영상이 시작되지 않았다"))
            }
            return
        }
        _ = currentAttempt
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.lock.withLock({ self.stopped }) else { return }
            self.connect()
        }
    }

    // MARK: - URLSessionDataDelegate

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }
        switch http.statusCode {
        case 200:
            completionHandler(.allow)
        case 401, 403:
            completionHandler(.cancel)
            handler(.failed("인증 거절 — 자격을 확인한다"))
        case 502, 503:
            // 스트리머가 아직 안 떴다. kvmd 세션은 열어 뒀으니 곧 뜬다.
            completionHandler(.cancel)
            retryAfterStartupDelay()
        default:
            completionHandler(.cancel)
            handler(.failed("HTTP \(http.statusCode)"))
        }
    }

    public func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data
    ) {
        let frames: [Data] = lock.withLock { splitter.append(data) }
        for frame in frames { handler(.frame(frame)) }
    }

    public func urlSession(
        _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
    ) {
        guard let error, (error as NSError).code != NSURLErrorCancelled else { return }
        guard !lock.withLock({ stopped }) else { return }
        handler(.failed(error.localizedDescription))
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            client.endpoint.allowsUntrustedCertificate,
            challenge.protectionSpace.host == client.endpoint.host,
            let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
