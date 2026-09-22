import Foundation
import os

private let logger = Logger(subsystem: "net.ranode.swiftkit", category: "storage-lifecycle")

/// APFS Sparsebundle 컨테이너 마운트 수명주기 및 하드링크 지원 진단 관리자
public struct StorageLifecycleManager: Sendable {
    private let sparsebundleAdapter: SparsebundleAdapter

    public init(sparsebundleAdapter: SparsebundleAdapter = .default) {
        self.sparsebundleAdapter = sparsebundleAdapter
    }

    /// 타깃 URL이 하드링크(POSIX link)를 지원하는지 진단
    public func supportsHardLinks(at url: URL) -> Bool {
        let isVolumesPath = url.pathComponents.dropFirst().first == "Volumes"
        if isVolumesPath {
            let testSrc = url.appendingPathComponent(".hl_test_src_\(UUID().uuidString)")
            let testDst = url.appendingPathComponent(".hl_test_dst_\(UUID().uuidString)")
            do {
                try Data().write(to: testSrc)
            } catch {
                return false
            }
            let linkOk = link(testSrc.path, testDst.path) == 0
            let fm = FileManager.default
            do {
                try fm.removeItem(at: testSrc)
                if linkOk {
                    try fm.removeItem(at: testDst)
                }
            } catch {
                _ = error
            }
            return linkOk
        }
        return true
    }

    /// 가상 APFS Sparsebundle 마운트 하에서 작업을 수행하고 종료 시 안전하게 분리하는 스코프 함수
    public func withMountedSparsebundle<T>(
        at url: URL,
        sizeGiB: Int = 2048,
        autoDetach: Bool = true,
        operation: (URL) async throws -> T
    ) async throws -> T {
        let bundleURL = sparsebundleAdapter.resolveBundleURL(from: url)
        let wasAlreadyMounted = sparsebundleAdapter.isMounted(bundleURL: bundleURL)

        let mountPoint = try sparsebundleAdapter.attachOrCreateSparsebundle(at: url, sizeGiB: sizeGiB)
        logger.info("Active APFS sparsebundle at \(mountPoint.path) (pre-existing: \(wasAlreadyMounted))")

        defer {
            if !wasAlreadyMounted && autoDetach {
                do {
                    try sparsebundleAdapter.detachSparsebundle(mountPoint: mountPoint)
                    logger.info("Detached APFS sparsebundle at \(mountPoint.path)")
                } catch {
                    logger.warning("Failed to detach sparsebundle at \(mountPoint.path): \(error.localizedDescription)")
                }
            }
        }

        return try await operation(mountPoint)
    }
}
