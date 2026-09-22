import Foundation
import FastDiskIOKit
import StateRootKit

/// 단일 인스턴스 격리 범위 및 경로 계산을 전담하는 Value Object.
public enum InstanceLockScope: Sendable, Equatable, Hashable {
    /// 호스트 머신/사용자 세션 전역 스코프
    case host(directory: URL? = nil)
    /// Git 워크트리 스코프 (동일 워크트리 내 중복 실행 차단)
    case worktree(root: URL? = nil)
    /// 특정 테넌트 격리 스코프 (동일 워크트리 또는 호스트 내 테넌트 단위 격리)
    case tenant(slug: String, root: URL? = nil)

    public static let host: InstanceLockScope = .host(directory: nil)
    public static let worktree: InstanceLockScope = .worktree(root: nil)

    /// Darwin UDS 경로 한계 (sockaddr_un.sun_path = 104 바이트, null 종료 문자 포함 103 바이트)
    public static let maxUDSPathLength: Int = 103

    /// 정규화된 스코프 고유 식별 키 생성
    public func canonicalKey(name: String) -> String {
        switch self {
        case .host(let dir):
            let path = dir?.standardizedFileURL.path ?? "/tmp"
            return "host:\(path):\(name)"
        case .worktree(let root):
            let baseDir = (root ?? Self.findWorktreeRoot()).standardizedFileURL.path
            return "worktree:\(baseDir):\(name)"
        case .tenant(let slug, let root):
            let baseDir = (root ?? FileManager.default.homeDirectoryForCurrentUser).standardizedFileURL.path
            return "tenant:\(slug):\(baseDir):\(name)"
        }
    }

    /// 파일시스템 상의 flock 락 파일 URL 계산
    public func lockFileURL(name: String) -> URL {
        let baseName = name.hasSuffix(".lock") ? String(name.dropLast(5)) : name
        switch self {
        case .host(let directory):
            let baseDir = directory ?? URL(fileURLWithPath: "/tmp")
            return baseDir.appendingPathComponent("\(baseName).lock")
        case .worktree(let root):
            let baseDir = (root ?? Self.findWorktreeRoot()).standardizedFileURL.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ".", with: "_")
            return URL(fileURLWithPath: "/tmp/\(baseName)-\(baseDir).lock")
        case .tenant(let slug, let root):
            let tenantRoot = root.map { $0.appendingPathComponent(".tenants", isDirectory: true) }
                ?? URL(fileURLWithPath: StateRootKit.tenantsRoot(), isDirectory: true)
            return tenantRoot.appendingPathComponent("\(slug)/.locks/\(baseName).lock")
        }
    }

    /// Darwin 104바이트 제약을 엄격히 준수하는 Unix Domain Socket URL 계산
    /// 반환 경로: `/tmp/sik_<16hex>.sock` (총 30자 이내 보장)
    public func socketURL(name: String) -> URL {
        let key = canonicalKey(name: name)
        return SingleInstance.socketURL(for: key)
    }

    /// Git Worktree 루트 디렉토리 탐색
    public static func findWorktreeRoot(
        from startURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> URL {
        let env = ProcessInfo.processInfo.environment
        if let environmentRoot = firstExistingRoot(in: env) { return environmentRoot }

        return nearestGitRoot(from: startURL) ?? startURL.standardizedFileURL
    }

    private static func firstExistingRoot(in environment: [String: String]) -> URL? {
        for key in ["ROOM_WORKTREE", "GIT_WORK_TREE"] {
            guard let path = environment[key], !path.isEmpty else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        return nil
    }

    private static func nearestGitRoot(from startURL: URL) -> URL? {
        var current = startURL.standardizedFileURL
        while true {
            let gitPath = current.appendingPathComponent(".git").path
            guard !FileManager.default.fileExists(atPath: gitPath) else { return current }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { return nil }
            current = parent
        }
    }
}
