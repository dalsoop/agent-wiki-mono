import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Mach 커널 통계 API(`mach_host_self()`, `host_statistics64`, `HOST_VM_INFO64`)를 사용해
/// fork 비용 0으로 호스트 가용 메모리를 측정하고 실질 가용 RAM 부족(2GB 미만) 시 컴파일/빌드를 차단하는 게이트.
public enum HostMemoryPressureGate: Sendable {
    /// 컴파일 보장을 위한 최소 가용 메모리 바이트 수 (2GB = 2 * 1024 * 1024 * 1024).
    public static let minimumAvailableMemoryBytes: UInt64 = 2 * 1024 * 1024 * 1024

    public struct Snapshot: Sendable, Equatable, Codable {
        /// 가용 메모리 바이트 수 (free + inactive + purgeable).
        public var availableBytes: UInt64
        /// 전체 물리 메모리 바이트 수 (`hw.memsize`).
        public var totalBytes: UInt64
        /// 최소 요구 가용 메모리 바이트 수.
        public var thresholdBytes: UInt64
        /// 가용 메모리가 임계값 미만이라 HOLD 여부.
        public var hold: Bool
        /// 판정 사유 ("ok" 또는 "low memory: X.XX GB < Y.YY GB").
        public var reason: String

        public init(
            availableBytes: UInt64,
            totalBytes: UInt64,
            thresholdBytes: UInt64 = HostMemoryPressureGate.minimumAvailableMemoryBytes,
            hold: Bool,
            reason: String
        ) {
            self.availableBytes = availableBytes
            self.totalBytes = totalBytes
            self.thresholdBytes = thresholdBytes
            self.hold = hold
            self.reason = reason
        }

        public init(
            hold: Bool,
            availableBytes: UInt64,
            thresholdBytes: UInt64 = HostMemoryPressureGate.minimumAvailableMemoryBytes,
            totalBytes: UInt64,
            reason: String
        ) {
            self.availableBytes = availableBytes
            self.totalBytes = totalBytes
            self.thresholdBytes = thresholdBytes
            self.hold = hold
            self.reason = reason
        }

        public var availableGB: Double {
            Double(availableBytes) / Double(1024 * 1024 * 1024)
        }

        public var thresholdGB: Double {
            Double(thresholdBytes) / Double(1024 * 1024 * 1024)
        }
    }

    /// 측정값을 직접 주입하여 테스트 시 호스트 실환경에 구애받지 않도록 하는 순수 snapshot 생성자.
    public static func snapshot(
        availableBytes: UInt64,
        totalBytes: UInt64,
        thresholdBytes: UInt64 = minimumAvailableMemoryBytes
    ) -> Snapshot {
        let hold = availableBytes < thresholdBytes
        let reason: String
        if hold {
            let availGBStr = String(format: "%.2f", Double(availableBytes) / Double(1024 * 1024 * 1024))
            let threshGBStr = String(format: "%.2f", Double(thresholdBytes) / Double(1024 * 1024 * 1024))
            reason = "available memory low (\(availGBStr)GB < \(threshGBStr)GB)"
        } else {
            reason = "ok"
        }
        return Snapshot(
            availableBytes: availableBytes,
            totalBytes: totalBytes,
            thresholdBytes: thresholdBytes,
            hold: hold,
            reason: reason
        )
    }

    /// 실시간 시스템 커널 정보를 읽어 Snapshot 생성.
    public static func check(thresholdBytes: UInt64 = minimumAvailableMemoryBytes) -> Snapshot {
        let available = readAvailableMemory()
        let total = readPhysicalMemory()
        return snapshot(availableBytes: available, totalBytes: total, thresholdBytes: thresholdBytes)
    }

    public static func shouldHold(thresholdBytes: UInt64 = minimumAvailableMemoryBytes) -> Bool {
        check(thresholdBytes: thresholdBytes).hold
    }

    /// `hw.memsize` sysctl 로 전체 물리 메모리를 fork 없이 직접 읽는다.
    public static func readPhysicalMemory() -> UInt64 {
        #if os(macOS)
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        return sysctlbyname("hw.memsize", &size, &len, nil, 0) == 0 ? size : 0
        #else
        return ProcessInfo.processInfo.physicalMemory
        #endif
    }

    /// Mach 커널 API `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)` 를 통해
    /// 프로세스 fork 비용 0으로 실질 가용 메모리(바이트)를 산출한다.
    /// 실질 가용 = (free_count + inactive_count + purgeable_count) * pageSize.
    public static func readAvailableMemory() -> UInt64 {
        #if os(macOS)
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        var info = vm_statistics64_data_t()
        let result = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return 0
        }
        let page = UInt64(pageSize)
        // 실질적으로 즉시 할당 가능한 메모리: free_count + inactive_count + purgeable_count
        let availablePages = UInt64(info.free_count) + UInt64(info.inactive_count) + UInt64(info.purgeable_count)
        return availablePages * page
        #else
        return 0
        #endif
    }
}
