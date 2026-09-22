import CommandKit
import Foundation

enum CommandKitSync {
    static func run(
        _ launchPath: String,
        _ arguments: [String],
        timeout: TimeInterval? = 30
    ) -> CommandResult {
        final class Box: @unchecked Sendable {
            var result: CommandResult?
        }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            let inner = DispatchSemaphore(value: 0)
            Task.detached {
                box.result = await ProcessCommandRunner().run(launchPath, arguments, timeout: timeout)
                inner.signal()
            }
            inner.wait()
            done.signal()
        }
        done.wait()
        return box.result ?? CommandResult(stdout: "", stderr: "command execution failed", exitCode: 127)
    }
}
