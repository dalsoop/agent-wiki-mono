#if canImport(Darwin) || canImport(Glibc)
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif


// MARK: - Process Wait State & Termination Monitoring

final class ProcessWaitState: Sendable {
    private struct State: Sendable {
        var isResumed = false
        var isTimedOut = false
        var timeoutTask: Task<Void, Never>?
    }
    private let state = LockedState(State())

    var isTimedOut: Bool {
        state.withLock { $0.isTimedOut }
    }

    func markTimedOut() {
        state.withLock { $0.isTimedOut = true }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        let alreadyResumed = state.withLock { s -> Bool in
            if s.isResumed {
                return true
            }
            s.timeoutTask = task
            return false
        }
        if alreadyResumed {
            task.cancel()
        }
    }

    func finish(continuation: CheckedContinuation<Void, Never>) {
        let (shouldResume, taskToCancel) = state.withLock { s -> (Bool, Task<Void, Never>?) in
            guard !s.isResumed else { return (false, nil) }
            s.isResumed = true
            let task = s.timeoutTask
            s.timeoutTask = nil
            return (true, task)
        }
        if shouldResume {
            taskToCancel?.cancel()
            continuation.resume()
        }
    }
}

func waitForProcessTermination(
    _ proc: Process,
    terminator: ProcessTerminator,
    timeout: TimeInterval?
) async -> (timedOut: Bool, exitCode: Int32) {
    guard proc.isRunning else {
        return (false, proc.terminationStatus)
    }

    let waitState = ProcessWaitState()

    await withTaskCancellationHandler {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            proc.terminationHandler = { _ in
                waitState.finish(continuation: continuation)
            }

            if !proc.isRunning {
                waitState.finish(continuation: continuation)
                return
            }

            if let timeout, timeout > 0 {
                let task = Task.detached {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                        waitState.markTimedOut()
                        terminator.terminate()
                    } catch is CancellationError {
                        return
                    } catch {
                        FileHandle.standardError.write(
                            Data("CommandKit ProcessRunner timeout task error: \(error.localizedDescription)\n".utf8)
                        )
                    }
                }
                waitState.setTimeoutTask(task)
            }
        }
    } onCancel: {
        terminator.cancel()
    }

    proc.terminationHandler = nil
    let timedOut = waitState.isTimedOut
    let exitCode = timedOut ? 124 : proc.terminationStatus
    return (timedOut, exitCode)
}

// MARK: - Process Group Isolation & Escalation

final class ProcessTerminator: Sendable {
    private struct State: Sendable {
        var pid: pid_t = 0
        var isGroupLeader = false
        var isCancelled = false
        var terminationInitiated = false
        var escalationTask: Task<Void, Never>?
    }
    private let state = LockedState(State())
    private let gracePeriod: TimeInterval

    init(gracePeriod: TimeInterval = 1.0) {
        self.gracePeriod = gracePeriod
    }

    func attach(process: Process, isGroupLeader: Bool = false) {
        let pid = process.processIdentifier
        let shouldTerminate = state.withLock { s -> Bool in
            s.pid = pid
            s.isGroupLeader = isGroupLeader
            return s.isCancelled && !s.terminationInitiated
        }
        if shouldTerminate {
            terminateGroup(pid: pid, isGroupLeader: isGroupLeader)
        }
    }

    func terminate() {
        let (pid, isGroupLeader) = state.withLock { s -> (pid_t, Bool) in
            s.isCancelled = true
            guard !s.terminationInitiated else { return (0, false) }
            s.terminationInitiated = true
            return (s.pid, s.isGroupLeader)
        }
        guard pid > 0 else { return }
        terminateGroup(pid: pid, isGroupLeader: isGroupLeader)
    }

    private func terminateGroup(pid: pid_t, isGroupLeader: Bool) {
        sendSignal(pid: pid, isGroupLeader: isGroupLeader, signal: SIGTERM)
        state.withLock { s in
            guard s.escalationTask == nil else { return }
            let grace = self.gracePeriod
            s.escalationTask = Task.detached {
                do {
                    try await Task.sleep(nanoseconds: UInt64(grace * 1_000_000_000))
                } catch {
                    return
                }
                #if canImport(Darwin) || canImport(Glibc)
                guard kill(pid, 0) == 0 else { return }
                #endif
                self.sendSignal(pid: pid, isGroupLeader: isGroupLeader, signal: SIGKILL)
            }
        }
    }

    private func sendSignal(pid: pid_t, isGroupLeader: Bool, signal: Int32) {
        #if canImport(Darwin) || canImport(Glibc)
        guard isGroupLeader else {
            _ = kill(pid, signal)
            return
        }
        _ = killpg(pid, signal)
        _ = kill(pid, signal)
        #endif
    }

    func cancel() {
        terminate()
    }

    func cleanup() {
        let task = state.withLock { s -> Task<Void, Never>? in
            let t = s.escalationTask
            s.escalationTask = nil
            s.pid = 0
            return t
        }
        task?.cancel()
    }
}
#endif
