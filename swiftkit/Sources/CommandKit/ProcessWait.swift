import Foundation

#if os(iOS)
/// iOS 스텁. Process 가 없다.
public enum ProcessWait {
    public static let defaultTimeout: TimeInterval = 8
}
#else
/// `waitUntilExit` 상한 + 대기 전 파이프 드레인.
public enum ProcessWait {
    public static let defaultTimeout: TimeInterval = 8

    /// 파이프 없는 워치독. 기본 30초(함대 hang 방지 관례).
    public static func untilExit(_ process: Process, seconds: TimeInterval = 30) {
        let dog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: dog)
        process.waitUntilExit()
        dog.cancel()
    }

    public static func drainAndWait(_ group: DispatchGroup) {
        group.wait()
    }

    public static func untilExit(
        _ process: Process,
        stdout: Pipe,
        stderr: Pipe,
        seconds: TimeInterval = defaultTimeout
    ) -> (Data, Data) {
        let outBox = DataBox()
        let errBox = DataBox()
        attachReadabilityHandlers(stdout: stdout, stderr: stderr, outBox: outBox, errBox: errBox)

        let dog = scheduleWatchdog(for: process, timeout: seconds)
        ensureProcessRunning(process)

        process.waitUntilExit()
        dog.cancel()

        detachAndDrainWithWaitDelay(stdout: stdout, stderr: stderr, outBox: outBox, errBox: errBox)
        return (outBox.data, errBox.data)
    }

    private static let watchdogQueue = DispatchQueue(
        label: "com.gujo.commandkit.processwait.watchdog",
        qos: .utility
    )

    private static let drainQueue = DispatchQueue(
        label: "com.gujo.commandkit.processwait.drain",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private static func attachReadabilityHandlers(
        stdout: Pipe, stderr: Pipe, outBox: DataBox, errBox: DataBox
    ) {
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            outBox.append(chunk)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            errBox.append(chunk)
        }
    }

    private static func scheduleWatchdog(for process: Process, timeout: TimeInterval) -> DispatchWorkItem {
        let dog = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
        }
        watchdogQueue.asyncAfter(deadline: .now() + timeout, execute: dog)
        return dog
    }

    private static func ensureProcessRunning(_ process: Process) {
        guard !process.isRunning else { return }
        do {
            try process.run()
        } catch {
            _ = error
        }
    }

    private static func detachAndDrainWithWaitDelay(
        stdout: Pipe, stderr: Pipe, outBox: DataBox, errBox: DataBox
    ) {
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

        let drainGroup = DispatchGroup()
        drainGroup.enter()
        drainQueue.async {
            outBox.append(stdout.fileHandleForReading.readDataToEndOfFile())
            drainGroup.leave()
        }

        drainGroup.enter()
        drainQueue.async {
            errBox.append(stderr.fileHandleForReading.readDataToEndOfFile())
            drainGroup.leave()
        }

        let waitResult = drainGroup.wait(timeout: .now() + ShellCommand.defaultWaitDelay)
        guard waitResult == .timedOut else { return }
        closeSilently(stdout.fileHandleForReading)
        closeSilently(stderr.fileHandleForReading)
    }

    private static func closeSilently(_ handle: FileHandle) {
        do {
            try handle.close()
        } catch {
            _ = error
        }
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
#endif
