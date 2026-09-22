import Foundation
#if os(macOS)
import Darwin
#endif

/// 응답하지 않는 privileged helper 를 내린 뒤 같은 plist 로 다시 올린다.
public struct PrivilegedHelperReplacer: Sendable {
    public var unloadWaitNanoseconds: UInt64
    public var unloadAttempts: Int

    public init(unloadWaitNanoseconds: UInt64 = 150_000_000, unloadAttempts: Int = 8) {
        self.unloadWaitNanoseconds = unloadWaitNanoseconds
        self.unloadAttempts = unloadAttempts
    }

    public func unload(_ daemon: PrivilegedHelperControlling) async throws {
        try await daemon.unregister()
        await waitUntilNotEnabled(daemon)
    }

    /// unregister → 대기 → register. ping 성공인 헬퍼에는 호출하지 말 것.
    public func replace(_ daemon: PrivilegedHelperControlling) async throws {
        try? await daemon.unregister()
        await waitUntilNotEnabled(daemon)
        do {
            try daemon.register()
        } catch {
            if daemon.status == .enabled {
                throw PrivilegedHelperError.stillEnabledAfterReplace
            }
            throw error
        }
    }

    private func waitUntilNotEnabled(_ daemon: PrivilegedHelperControlling) async {
        for _ in 0..<unloadAttempts {
            if daemon.status != .enabled { return }
            try? await Task.sleep(nanoseconds: unloadWaitNanoseconds)
        }
    }
}

#if os(macOS)
/// launchd 가 SMAppService.notFound 인데도 헬퍼 프로세스가 남은 경우.
public enum PrivilegedHelperProcessOccupancy {
    public static func isOccupied(pathContains token: String) -> Bool {
        let needle = token.lowercased()
        guard !needle.isEmpty else { return false }
        let byteCount = proc_listallpids(nil, 0)
        guard byteCount > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: (Int(byteCount) / MemoryLayout<pid_t>.stride) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard filled > 0 else { return false }
        let count = Int(filled) / MemoryLayout<pid_t>.stride
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            let n = proc_pidpath(pid, &buffer, UInt32(MAXPATHLEN))
            guard n > 0 else { continue }
            let path = String(decoding: buffer.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self).lowercased()
            if path.contains(needle) { return true }
        }
        return false
    }

    /// 떠 있는 헬퍼가 `file` 보다 먼저 시작됐으면 옛 바이너리다.
    public static func isProcessOlderThanFile(pathContains token: String, file: URL) -> Bool {
        guard let mtime = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date else {
            return false
        }
        let mtimeSec = mtime.timeIntervalSince1970
        let needle = token.lowercased()
        guard !needle.isEmpty else { return false }
        let byteCount = proc_listallpids(nil, 0)
        guard byteCount > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: (Int(byteCount) / MemoryLayout<pid_t>.stride) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.stride))
        guard filled > 0 else { return false }
        let count = Int(filled) / MemoryLayout<pid_t>.stride
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            let n = proc_pidpath(pid, &buffer, UInt32(MAXPATHLEN))
            guard n > 0 else { continue }
            let path = String(decoding: buffer.prefix(Int(n)).map { UInt8(bitPattern: $0) }, as: UTF8.self).lowercased()
            guard path.contains(needle) else { continue }
            var bsd = proc_bsdinfo()
            let sz = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, Int32(MemoryLayout<proc_bsdinfo>.stride))
            guard sz > 0 else { continue }
            let start = TimeInterval(bsd.pbi_start_tvsec) + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000
            if start + 1 < mtimeSec { return true }
        }
        return false
    }
}
#endif
