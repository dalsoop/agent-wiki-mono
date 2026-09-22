import Foundation

/// 프로세스 생명주기 스코프 및 리소스 정리를 조율하는 코디네이터.
public enum ProcessExitCoordinator {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var atexitRegistered = false
    nonisolated(unsafe) private static var exitHandlers: [@Sendable () -> Void] = []

    /// 정상 또는 비정상 프로세스 종료 시 반드시 실행되어야 하는 리소스 정리 블록을 등록한다.
    public static func registerExitHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        exitHandlers.append(handler)

        if !atexitRegistered {
            atexitRegistered = true
            atexit {
                ProcessExitCoordinator.runHandlers()
            }
        }
    }

    /// 수동으로 클린업 핸들러들을 실행한다 (테스트 또는 명시적 셧다운 시).
    public static func runHandlers() {
        lock.lock()
        let handlers = exitHandlers
        exitHandlers.removeAll()
        lock.unlock()

        for handler in handlers {
            handler()
        }
    }

    /// 테스트용 리셋
    public static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        exitHandlers.removeAll()
    }
}
