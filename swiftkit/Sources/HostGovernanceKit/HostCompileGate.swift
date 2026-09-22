import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// 호스트 컴파일 및 과부하 판정 게이트.
public enum HostCompileGate: Sendable {
    public static let loadPerCoreLimit: Double = 0.8

    public struct Snapshot: Sendable, Equatable, Codable {
        public var load1: Double
        public var ncpu: Int
        public var loadPerCore: Double
        public var frontendCount: Int
        public var hold: Bool
        public var reason: String

        public init(
            load1: Double,
            ncpu: Int,
            loadPerCore: Double,
            frontendCount: Int,
            hold: Bool,
            reason: String
        ) {
            self.load1 = load1
            self.ncpu = ncpu
            self.loadPerCore = loadPerCore
            self.frontendCount = frontendCount
            self.hold = hold
            self.reason = reason
        }
    }

    /// 측정값을 주입하면 테스트가 호스트 부하에 안 묶인다.
    public static func snapshot(load1: Double, frontendCount: Int, ncpu: Int = 0) -> Snapshot {
        let cores = max(ncpu > 0 ? ncpu : ProcessInfo.processInfo.processorCount, 1)
        let perCore = load1 / Double(cores)
        var parts: [String] = []
        if frontendCount >= cores {
            parts.append("swift-frontend \(frontendCount)≥\(cores)")
        }
        return Snapshot(
            load1: load1,
            ncpu: cores,
            loadPerCore: perCore,
            frontendCount: frontendCount,
            hold: !parts.isEmpty,
            reason: parts.isEmpty ? "ok" : parts.joined(separator: ", ")
        )
    }

    public static func snapshot() -> Snapshot {
        snapshot(
            load1: readLoad1(),
            frontendCount: countSwiftFrontend(),
            ncpu: ProcessInfo.processInfo.processorCount
        )
    }

    public static func shouldHold() -> Bool {
        snapshot().hold
    }

    /// `getloadavg(3)` 로 1분 부하율 조회
    public static func readLoad1() -> Double {
        #if os(macOS)
        var averages = [Double](repeating: 0, count: 3)
        guard getloadavg(&averages, 3) == 3 else { return 0 }
        return averages[0]
        #else
        return 0
        #endif
    }

    /// `sysctl(KERN_PROC_ALL)` 로 swift-frontend 프로세스 개수를 직접 계산
    public static func countSwiftFrontend() -> Int {
        #if os(macOS)
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return 0 }
        var processes = [kinfo_proc](
            repeating: kinfo_proc(),
            count: size / MemoryLayout<kinfo_proc>.stride
        )
        guard sysctl(&mib, 4, &processes, &size, nil, 0) == 0 else { return 0 }
        let count = size / MemoryLayout<kinfo_proc>.stride
        var matches = 0
        for index in 0..<count {
            matches += withUnsafeBytes(of: &processes[index].kp_proc.p_comm) { raw in
                let name = String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                return name == "swift-frontend" ? 1 : 0
            }
        }
        return matches
        #else
        return 0
        #endif
    }
}
