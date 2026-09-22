import Foundation

/// 파일 시스템에서 마크다운(.md) 파일들을 수집하는 추상 프로토콜.
public protocol MarkdownFileCollector: Sendable {
    func collect(under root: URL, limit: Int?) -> [URL]
}

public extension MarkdownFileCollector {
    func collect(under root: URL) -> [URL] {
        collect(under: root, limit: nil)
    }
}

/// DriftScanWalk 기반의 기본 마크다운 수집기.
/// .git, .build, node_modules, DerivedData 등의 빌드/저장소 내부와 심링크 순회를 안전하게 회피합니다.
public struct DefaultMarkdownFileCollector: MarkdownFileCollector {
    public static let defaultSkipDirs: Set<String> = [
        ".git", ".build", "node_modules", ".worktrees", "DerivedData",
        ".wiki", "Pods", "vendor", "third_party"
    ]

    public let skipDirs: Set<String>
    public let includeSymlinks: Bool

    public init(
        skipDirs: Set<String> = defaultSkipDirs,
        includeSymlinks: Bool = false
    ) {
        self.skipDirs = skipDirs
        self.includeSymlinks = includeSymlinks
    }

    public static func isSymlinkedDirectory(_ u: URL) -> Bool {
        resourceFlag(u, key: .isSymbolicLinkKey)
    }

    public static func isSymlinkFile(_ u: URL) -> Bool {
        resourceFlag(u, key: .isSymbolicLinkKey)
    }

    public func collect(under root: URL, limit: Int? = nil) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else {
            return []
        }
        var docs: [URL] = []
        for case let u as URL in enumerator {
            appendIfMarkdown(u, enumerator: enumerator, docs: &docs, limit: limit)
            if let limit, docs.count >= limit {
                break
            }
        }
        return docs.sorted { $0.path < $1.path }
    }

    private func appendIfMarkdown(
        _ u: URL,
        enumerator: FileManager.DirectoryEnumerator,
        docs: inout [URL],
        limit: Int?
    ) {
        let isDir = resourceFlag(u, key: .isDirectoryKey) || u.hasDirectoryPath
        let isSymlink = resourceFlag(u, key: .isSymbolicLinkKey)
        if isDir {
            skipIfNeeded(u, isSymlink: isSymlink, enumerator: enumerator)
            return
        }
        let isMarkdown = u.pathExtension.lowercased() == "md"
        let acceptLink = includeSymlinks || !isSymlink
        guard isMarkdown && acceptLink else { return }
        docs.append(u)
    }

    private func skipIfNeeded(
        _ u: URL,
        isSymlink: Bool,
        enumerator: FileManager.DirectoryEnumerator
    ) {
        let shouldSkip = skipDirs.contains(u.lastPathComponent) || isSymlink
        guard shouldSkip else { return }
        enumerator.skipDescendants()
    }

    private static func resourceFlag(_ u: URL, key: URLResourceKey) -> Bool {
        do {
            let values = try u.resourceValues(forKeys: [key])
            switch key {
            case .isDirectoryKey:
                return values.isDirectory ?? false
            case .isSymbolicLinkKey:
                return values.isSymbolicLink ?? false
            default:
                return false
            }
        } catch {
            return false
        }
    }

    private func resourceFlag(_ u: URL, key: URLResourceKey) -> Bool {
        Self.resourceFlag(u, key: key)
    }
}
