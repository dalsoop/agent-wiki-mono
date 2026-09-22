import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 프로세스 종료 시그널(SIGINT, SIGTERM)을 안전하게 가로채 등록된 클린업 핸들러를 실행한 뒤 종료하는 SSOT.
/// 룸 좌석 반납, StateMirror 세션 정리, 임시 파일 삭제를 보장하여 좀비 프로세스와 잔여 락을 방지합니다.
public final class ProcessSignalTrap: @unchecked Sendable {
    public static let shared = ProcessSignalTrap()

    private let lock = NSLock()
    private var cleanups: [CleanupHandler] = []
    private var isInstalled = false
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?
    private let queue = DispatchQueue(label: "net.ranode.process-signal-trap", qos: .userInitiated)

    public struct CleanupHandler: Sendable {
        public let name: String
        public let action: @Sendable (Int32) -> Void

        public init(name: String, action: @escaping @Sendable (Int32) -> Void) {
            self.name = name
            self.action = action
        }
    }

    private init() {}

    /// 종료 시 실행될 클린업 핸들러를 등록한다.
    /// - Parameters:
    ///   - name: 핸들러 이름 (디버깅/로깅용)
    ///   - action: 수신된 시그널 번호(SIGINT=2, SIGTERM=15)를 인자로 받는 클린업 블록
    public func onSignal(name: String, action: @escaping @Sendable (Int32) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        cleanups.append(CleanupHandler(name: name, action: action))
    }

    /// 시그널 트랩을 운영체제에 설치한다.
    /// 이미 설치되어 있으면 추가 설치하지 않는다.
    public func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !isInstalled else { return }
        isInstalled = true

        #if canImport(Darwin)
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: queue)
        intSource.setEventHandler { [weak self] in
            self?.handleSignal(SIGINT, exitCode: 130)
        }
        intSource.resume()
        self.sigintSource = intSource

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        termSource.setEventHandler { [weak self] in
            self?.handleSignal(SIGTERM, exitCode: 143)
        }
        termSource.resume()
        self.sigtermSource = termSource
        #endif
    }

    /// 수신된 시그널 처리 및 등록된 클린업 실행
    public func handleSignal(_ signalNum: Int32, exitCode: Int32, shouldExit: Bool = true) {
        lock.lock()
        let handlers = cleanups
        lock.unlock()

        for handler in handlers {
            handler.action(signalNum)
        }

        #if canImport(Darwin) || canImport(Glibc)
        if shouldExit {
            exit(exitCode)
        }
        #endif
    }

    /// 테스트용 핸들러 초기화
    public func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        cleanups.removeAll()
        sigintSource?.cancel()
        sigtermSource?.cancel()
        sigintSource = nil
        sigtermSource = nil
        isInstalled = false
    }

    /// 등록된 클린업 핸들러 수 (테스트용)
    public var registeredCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return cleanups.count
    }
}
