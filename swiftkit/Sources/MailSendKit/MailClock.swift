import Foundation

/// 발송·보관·rate limit 시각. 테스트는 고정 시계를 주입한다.
public protocol MailClock: Sendable {
    var now: Date { get }
    func sleep(seconds: TimeInterval) async
}

public struct SystemMailClock: MailClock {
    public init() {}

    public var now: Date { Date() }

    public func sleep(seconds: TimeInterval) async {
        guard seconds > 0 else { return }
        let nanos = UInt64(seconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }
}

public final class ControllableMailClock: MailClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date
    public private(set) var sleeps: [TimeInterval] = []

    public init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.instant = now
    }

    public var now: Date {
        withLock { instant }
    }

    public func advance(by seconds: TimeInterval) {
        withLock { instant = instant.addingTimeInterval(seconds) }
    }

    public func set(_ date: Date) {
        withLock { instant = date }
    }

    public func sleep(seconds: TimeInterval) async {
        withLock {
            sleeps.append(seconds)
            instant = instant.addingTimeInterval(max(0, seconds))
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
