import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Apple Silicon P/E 코어 및 시스템 하드웨어 프로파일 SSOT.
public struct HostHardwareProfile: Sendable, Equatable, Codable {
    public let totalLogicalCores: Int
    public let performanceCores: Int
    public let efficiencyCores: Int
    public let safeCompileQuota: Int

    public init(
        totalLogicalCores: Int,
        performanceCores: Int,
        efficiencyCores: Int,
        safeCompileQuota: Int
    ) {
        self.totalLogicalCores = totalLogicalCores
        self.performanceCores = performanceCores
        self.efficiencyCores = efficiencyCores
        self.safeCompileQuota = safeCompileQuota
    }

    /// 현재 머신의 하드웨어 프로파일 감지.
    public static func current() -> HostHardwareProfile {
        let total = ProcessInfo.processInfo.processorCount
        #if os(macOS)
        let pCores = readSysctlInt("hw.perflevel0.logicalcpu") ?? total
        let eCores = readSysctlInt("hw.perflevel1.logicalcpu") ?? 0
        let quota = max(1, pCores - 1)
        return HostHardwareProfile(
            totalLogicalCores: total,
            performanceCores: pCores,
            efficiencyCores: eCores,
            safeCompileQuota: quota
        )
        #else
        return HostHardwareProfile(
            totalLogicalCores: total,
            performanceCores: total,
            efficiencyCores: 0,
            safeCompileQuota: max(1, total - 1)
        )
        #endif
    }

    #if os(macOS)
    private static func readSysctlInt(_ name: String) -> Int? {
        var val: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &val, &size, nil, 0) == 0 else {
            return nil
        }
        return Int(val)
    }
    #endif
}
