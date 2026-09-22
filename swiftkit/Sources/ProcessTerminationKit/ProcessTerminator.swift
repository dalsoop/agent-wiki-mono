import Darwin
import Foundation
import PrivilegedKit

/// 프로세스 종료 결과
public enum ProcessTerminationResult: Equatable, Sendable {
    /// NSRunningApplication.terminate() 로 우아하게 정상 종료됨
    case graceful
    /// NSRunningApplication.forceTerminate() 로 강제 종료됨
    case forceQuit
    /// POSIX SIGKILL 신호로 사살됨
    case killed
    /// 관리자 권한(Privileged Escalation)을 통해 강제 종료됨
    case privilegedKilled
    /// 이미 종료되어 존재하지 않음
    case alreadyExited
    /// 종료 시도 실패 (권한 거부 또는 시간 초과)
    case failed(String)

    /// 정상 종료되었거나 이미 존재하지 않는 성공 상태 여부
    public var isSuccess: Bool {
        switch self {
        case .graceful, .forceQuit, .killed, .privilegedKilled, .alreadyExited:
            return true
        case .failed:
            return false
        }
    }
}

/// 3단계 에스컬레이션 및 프로세스 트리(Kill Tree) 종료 엔진
public enum ProcessTerminator {
    /// 프로세스가 실제로 살아있는지 확인
    public static func isAlive(pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    /// 단일 프로세스 종료 에스컬레이션
    /// 1) POSIX SIGTERM 전송
    /// 2) 타임아웃 후 격리된 프로세스 그룹에 SIGKILL 에스컬레이션
    /// 3) EPERM 시 PrivilegedRunner를 통한 관리자 종료 시도
    @discardableResult
    public static func terminate(
        pid: pid_t,
        bundleId: String? = nil,
        timeout: TimeInterval = 1.2,
        allowPrivilegedFallback: Bool = false
    ) async -> ProcessTerminationResult {
        _ = bundleId
        guard isAlive(pid: pid) else { return .alreadyExited }
        let graceful = await send(signal: SIGTERM, to: pid, timeout: timeout)
        if graceful == .exited { return .graceful }
        let forced = await forceTerminateIsolatedGroup(containing: pid, timeout: 0.5)
        switch forced {
        case .exited:
            return .killed
        case .permissionDenied where allowPrivilegedFallback:
            return await privilegedKill(pid: pid)
        default:
            return isAlive(pid: pid)
                ? .failed("Process \(pid) did not exit within timeout")
                : .killed
        }
    }

    /// 자식 프로세스 트리를 포함하여 프로세스 계층 전체를 안전하게 종료 (Kill Tree)
    /// 후손 프로세스를 leaf 노드부터 역순으로 사살한 뒤 루트 프로세스를 종료함
    @discardableResult
    public static func terminateTree(
        rootPID: pid_t,
        bundleId: String? = nil,
        timeout: TimeInterval = 1.0,
        allowPrivilegedFallback: Bool = false
    ) async -> [pid_t: ProcessTerminationResult] {
        var results: [pid_t: ProcessTerminationResult] = [:]

        // 1. 모든 후손 프로세스 수집 (Leaf부터 정렬됨)
        let descendants = ProcessTreeScanner.allDescendantPIDs(rootPID: rootPID)
        for childPID in descendants {
            let res = await terminate(
                pid: childPID,
                timeout: 0.3,
                allowPrivilegedFallback: allowPrivilegedFallback
            )
            results[childPID] = res
        }

        // 2. 루트 프로세스 최종 종료
        let rootRes = await terminate(
            pid: rootPID,
            bundleId: bundleId,
            timeout: timeout,
            allowPrivilegedFallback: allowPrivilegedFallback
        )
        results[rootPID] = rootRes

        return results
    }

    // MARK: - Internal Helpers

    private enum SignalResult { case exited, permissionDenied, failed }

    private static func send(signal: Int32, to pid: pid_t, timeout: TimeInterval) async -> SignalResult {
        guard kill(pid, signal) == 0 else {
            return errno == EPERM ? .permissionDenied : .failed
        }
        return await waitForExit(pid: pid, timeout: timeout) ? .exited : .failed
    }

    private static func forceTerminateIsolatedGroup(
        containing pid: pid_t,
        timeout: TimeInterval
    ) async -> SignalResult {
        let groupID = getpgid(pid)
        guard groupID > 0, groupID != getpgrp() else { return .failed }
        guard killpg(groupID, SIGKILL) == 0 else {
            return errno == EPERM ? .permissionDenied : .failed
        }
        return await waitForExit(pid: pid, timeout: timeout) ? .exited : .failed
    }

    private static func privilegedKill(pid: pid_t) async -> ProcessTerminationResult {
        let groupID = getpgid(pid)
        guard groupID > 0, groupID != getpgrp() else {
            return .failed("Refused to force-kill a shared process group")
        }
        let result = await PrivilegedRunner().run(["/bin/kill -9 -\(groupID)"])
        return result.exitCode == 0
            ? .privilegedKilled
            : .failed("Privileged kill failed: \(result.stderr)")
    }

    private static func waitForExit(pid: pid_t, timeout: TimeInterval) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while clock.now < deadline {
            if !isAlive(pid: pid) { return true }
            do {
                try await clock.sleep(for: .milliseconds(50))
            } catch {
                return !isAlive(pid: pid)
            }
        }
        return !isAlive(pid: pid)
    }
}
