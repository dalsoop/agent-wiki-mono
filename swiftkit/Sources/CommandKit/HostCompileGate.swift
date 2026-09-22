import Foundation

/// 호스트 컴파일·ship 한 줄 게이트.
/// BQ · ADM ship-queue · lint-batch 가 같은 한도를 본다.
/// `swift-frontend` 개수가 코어 수 이상이면 큐를 놀린다.
/// load1 은 관측만 하고 hold 하지 않는다 — WindowServer 로드에 ship 이 영구 HOLD 되던 사고를 끊는다.
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
        snapshot(load1: readLoad1(), frontendCount: countSwiftFrontend(), ncpu: ProcessInfo.processInfo.processorCount)
    }

    public static func shouldHold() -> Bool { snapshot().hold }

    /// `getloadavg(3)` 가 `uptime` 이 찍는 값과 같은 커널 카운터다 — fork 없이 읽는다.
    /// 이전 구현은 폴·게이트 검사마다 /usr/bin/uptime 을 띄웠다(게이트가 지키려는
    /// 과부하의 원인에 게이트 자신이 기여).
    public static func readLoad1() -> Double {
        #if os(macOS)
        var averages = [Double](repeating: 0, count: 3)
        guard getloadavg(&averages, 3) == 3 else { return 0 }
        return averages[0]
        #else
        return 0
        #endif
    }

    /// `sysctl(KERN_PROC_ALL)` 로 프로세스 테이블을 직접 훑는다 — pgrep fork 제거.
    /// `pgrep -lf` 는 커맨드라인 전체를 봤지만 여기서는 p_comm 을 본다: 오히려
    /// "인자에 swift-frontend 가 포함된 셸" 같은 오탐이 사라진다.
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
