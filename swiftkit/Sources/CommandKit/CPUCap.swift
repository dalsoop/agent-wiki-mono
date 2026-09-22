import Foundation

/// 워크스테이션 컴파일 병렬도 정본.
/// 잡 하나당 `-j` 와 셸 러너 concurrent 를 여기서만 계산한다.
public enum CPUCap: Sendable {
    public static func safeJobCount(
        ncpu: Int = ProcessInfo.processInfo.processorCount,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        if let envVal = environment["SWIFT_BUILD_JOBS"],
           let jobs = Int(envVal), jobs > 0 {
            return jobs
        }
        if ncpu <= 4 {
            return max(1, ncpu - 1)
        }
        if ncpu <= 8 {
            return 3
        }
        return 4
    }

    public static var flagString: String {
        "-j \(safeJobCount())"
    }

    /// 로그인 맥 셸 러너 동시 잡. 전용 CI 상자가 아니다.
    /// 8코어 16GB 실측: 4는 흔들림, 1은 너무 느림 → 2.
    public static func safeWorkstationRunnerConcurrent(
        ncpu: Int = ProcessInfo.processInfo.processorCount,
        memoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> Int {
        let memoryGB = Int(memoryBytes / 1_000_000_000)
        if ncpu <= 4 || memoryGB < 12 {
            return 1
        }
        return 2
    }
}
