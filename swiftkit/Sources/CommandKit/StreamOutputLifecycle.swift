import Foundation

final class StreamOutputLifecycle: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "CommandKit.StreamOutputLifecycle")
    private let onOutput: @Sendable (String) -> Void
    private var sealed = false

    init(onOutput: @escaping @Sendable (String) -> Void) {
        self.onOutput = onOutput
    }

    func receive(_ read: @escaping @Sendable () -> Data) {
        lock.lock()
        guard !sealed else {
            lock.unlock()
            return
        }
        queue.async { [onOutput] in
            let data = read()
            if !data.isEmpty {
                onOutput(String(decoding: data, as: UTF8.self))
            }
        }
        lock.unlock()
    }

    func complete(
        exitCode: Int32,
        finalRead: @escaping @Sendable () -> Data,
        onComplete: @escaping @Sendable (Int32) -> Void
    ) {
        lock.lock()
        guard !sealed else {
            lock.unlock()
            return
        }
        sealed = true
        queue.async { [onOutput] in
            let data = finalRead()
            if !data.isEmpty {
                onOutput(String(decoding: data, as: UTF8.self))
            }
            onComplete(exitCode)
        }
        lock.unlock()
    }
}
