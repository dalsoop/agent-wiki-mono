#if canImport(Darwin)
import Darwin
import notify
#endif
import Foundation
import Combine

/// Darwin 커널 시그널 기반의 양방향 실시간 동기화 엔진.
/// CLI 또는 다른 프로세스에서 상태를 변경했을 때 `StateMirrorSignal.post(app:)`를 호출하면,
/// 이를 관찰 중인 GUI(`StateMirrorWatcher`)에 0ms 지연으로 통지된다.
public enum StateMirrorSignal {
    /// Darwin notification 식별자 생성.
    public static func notificationName(for app: String) -> String {
        "com.gujo.statemirror.\(app)"
    }

    /// Darwin 커널 알림을 브로드캐스트한다.
    @discardableResult
    public static func post(app: String) -> Bool {
        #if canImport(Darwin)
        let name = notificationName(for: app)
        let status = notify_post(name)
        return status == NOTIFY_STATUS_OK
        #else
        return false
        #endif
    }
}

/// `notify_register_dispatch`를 사용하여 CLI 또는 다른 프로세스의 상태 변경을 0ms로 감지하고
/// 클로저 또는 Combine Publisher로 알림을 전달하는 관찰자.
public final class StateMirrorWatcher: @unchecked Sendable {
    public let app: String
    private let queue: DispatchQueue
    private var token: Int32 = -1
    private let subject = PassthroughSubject<Void, Never>()
    private let lock = NSLock()
    private var isCancelled = false

    /// Combine Publisher: 상태 변경 시 Void 이벤트를 방출한다.
    public var publisher: AnyPublisher<Void, Never> {
        subject.eraseToAnyPublisher()
    }

    /// 특정 앱의 StateMirror 상태 변경을 감지하는 Watcher를 생성한다.
    /// - Parameters:
    ///   - app: 관찰 대상 앱 식별자
    ///   - queue: 알림 콜백을 디스패치할 큐 (기본값: .main)
    ///   - onChange: 상태 변경 감지 시 호출될 클로저 (선택)
    public init(
        app: String,
        queue: DispatchQueue = .main,
        onChange: (@Sendable () -> Void)? = nil
    ) {
        self.app = app
        self.queue = queue

        #if canImport(Darwin)
        let name = StateMirrorSignal.notificationName(for: app)
        var registrationToken: Int32 = -1

        let status = notify_register_dispatch(
            name,
            &registrationToken,
            queue
        ) { [weak self] _ in
            guard let self = self else { return }
            self.lock.lock()
            let cancelled = self.isCancelled
            self.lock.unlock()
            guard !cancelled else { return }

            self.subject.send()
            onChange?()
        }

        if status == NOTIFY_STATUS_OK {
            self.token = registrationToken
        }
        #endif
    }

    deinit {
        cancel()
    }

    /// 관찰 등록을 해제하고 리소스를 정리한다.
    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        isCancelled = true

        #if canImport(Darwin)
        if token != -1 {
            notify_cancel(token)
            token = -1
        }
        #endif
        subject.send(completion: .finished)
    }
}

/// 원자적 파일 교체 및 파일 프레젠터 헬퍼.
public enum StateMirrorFilePresenter {
    /// 원자적 쓰기 헬퍼 (임시 파일 작성 후 atomic replace).
    public static func atomicWrite(data: Data, to destinationURL: URL) throws {
        try AtomicFileWriter().write(data, to: destinationURL)
    }
}
