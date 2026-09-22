import Darwin
import Foundation

/// macOS libproc 기반 프로세스 계층 트리 수집기 (Kill Tree용)
public enum ProcessTreeScanner {
    /// 특정 부모 PID의 직계 자식 프로세스 PID 목록을 반환
    public static func childPIDs(of parentPID: pid_t) -> [pid_t] {
        guard parentPID > 0 else { return [] }

        // 필요한 버퍼 크기 조회
        let bufferSize = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(parentPID), nil, 0)
        guard bufferSize > 0 else { return [] }

        let count = Int(bufferSize) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: count)
        let actualSize = proc_listpids(UInt32(PROC_PPID_ONLY), UInt32(parentPID), &pids, bufferSize)
        guard actualSize > 0 else { return [] }

        let actualCount = Int(actualSize) / MemoryLayout<pid_t>.stride
        return pids.prefix(actualCount).filter { $0 > 0 && $0 != parentPID }
    }

    /// 특정 루트 PID의 모든 후손(자식, 손자 등) 프로세스 PID들을 후위 순회(Leaf부터) 순서로 수집
    /// (자식을 먼저 죽여야 고아 프로세스나 좀비가 남지 않음)
    public static func allDescendantPIDs(rootPID: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var visited = Set<pid_t>()

        func dfs(_ current: pid_t) {
            guard !visited.contains(current) else { return }
            visited.insert(current)

            let children = childPIDs(of: current)
            for child in children {
                dfs(child)
            }
            if current != rootPID {
                result.append(current)
            }
        }

        dfs(rootPID)
        return result
    }

    /// 특정 PID의 상주 메모리(RSS) 크기를 MB 단위로 반환
    public static func residentMemoryMB(pid: pid_t) -> UInt64? {
        guard pid > 0 else { return nil }
        var info = proc_taskinfo()
        let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
        guard size == MemoryLayout<proc_taskinfo>.size else { return nil }
        return info.pti_resident_size / (1024 * 1024)
    }
}
