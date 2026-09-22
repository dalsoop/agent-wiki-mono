#if GujoManaged
import Foundation

enum GujoManagedProcessRunner {
    static func run(_ path: String, _ args: [String]) async -> [String: Any]? {
        guard let data = await runData(path, args) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    /// `software list --json` 처럼 최상위가 배열인 응답용.
    static func runArray(_ path: String, _ args: [String]) async -> [[String: Any]]? {
        guard let data = await runData(path, args) else { return nil }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        } catch {
            return nil
        }
    }

    static func runData(_ path: String, _ args: [String]) async -> Data? {
        #if os(macOS)
        await withCheckedContinuation { cont in
            Task.detached {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                let out = Pipe()
                let err = Pipe()
                p.standardOutput = out
                p.standardError = err
                do {
                    try p.run()
                } catch {
                    cont.resume(returning: nil)
                    return
                }

                let drainTask = Task.detached {
                    _ = err.fileHandleForReading.readDataToEndOfFile()
                }

                let watchdog = Task.detached {
                    do {
                        try await Task.sleep(nanoseconds: 5_000_000_000)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, p.isRunning else { return }
                    p.terminate()
                    do {
                        try await Task.sleep(nanoseconds: 2_000_000_000)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, p.isRunning else { return }
                    kill(p.processIdentifier, SIGKILL)
                }

                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                watchdog.cancel()
                _ = drainTask
                guard p.terminationStatus == 0 else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: data)
            }
        }
        #else
        _ = path
        _ = args
        return nil
        #endif
    }
}
#endif
