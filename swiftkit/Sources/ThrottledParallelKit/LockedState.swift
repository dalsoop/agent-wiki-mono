import Foundation

/// `os.OSAllocatedUnfairLock` 대체. Linux `swift:6.1` 에는 `import os` 가 없다.
final class LockedState<T>: Sendable {
    private let lock = NSLock()
    private nonisolated(unsafe) var value: T

    init(_ value: T) {
        self.value = value
    }

    func withLock<R>(_ body: (inout T) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
