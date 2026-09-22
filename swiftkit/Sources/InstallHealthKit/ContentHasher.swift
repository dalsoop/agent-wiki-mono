#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation

/// 대상 디렉터리의 소스 파일(*.swift, Package.swift, package-identity.json 등)을 수집하여
/// 정렬 후 결정론적 SHA-256 머클/트리 해시를 계산한다.
/// .git, .build 등 빌드 산출물 및 버전 관리 디렉터리는 제외한다.
public enum ContentHasher: Sendable {

    /// 소스 파일 기본 확장자 목록
    public static let defaultSourceExtensions: Set<String> = [
        "swift",
        "strings",
        "plist",
        "json",
        "xcassets",
        "entitlements",
        "png",
        "icns",
        "c",
        "h",
        "m",
        "mm",
        "cpp",
        "metal",
    ]

    /// 확장자와 무관하게 이름으로 포함할 소스 파일 목록
    public static let defaultSourceFileNames: Set<String> = [
        "Package.swift",
        "Package.resolved",
        "package-identity.json",
    ]

    /// 제외할 디렉터리 이름 목록 (.git, .build 등 빌드 산출물/버전 관리 제외)
    public static let defaultExcludedDirectories: Set<String> = [
        ".git",
        ".build",
        ".worktrees",
        "DerivedData",
        ".swiftpm",
        ".agent-ops",
    ]

    /// 임의 Data의 SHA-256 16진수 문자열 계산
    public static func sha256Hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        preconditionFailure("CryptoKit is required for sha256Hex on this platform")
        #endif
    }

    /// 파일 URL의 SHA-256 16진수 문자열 계산
    public static func sha256Hex(fileAt url: URL) -> String? {
        do {
            let data = try Data(contentsOf: url)
            return sha256Hex(data)
        } catch {
            return nil
        }
    }

    /// 대상 디렉터리의 소스 파일들을 정렬하여 결정론적 머클/트리 SHA-256 해시를 계산한다.
    ///
    /// - Parameters:
    ///   - directoryURL: 탐색할 디렉터리 URL
    ///   - includedExtensions: 포함할 확장자 집합 (기본값: defaultSourceExtensions)
    ///   - includedFileNames: 포함할 파일 이름 집합 (기본값: defaultSourceFileNames)
    ///   - excludedDirectoryNames: 제외할 디렉터리 집합 (기본값: defaultExcludedDirectories)
    /// - Returns: 계산된 SHA-256 해시 (대상 파일이 없으면 nil)
    public static func computeHash(
        for directoryURL: URL,
        includedExtensions: Set<String> = defaultSourceExtensions,
        includedFileNames: Set<String> = defaultSourceFileNames,
        excludedDirectoryNames: Set<String> = defaultExcludedDirectories
    ) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directoryURL.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }

        var entries: [(relativePath: String, hash: String)] = []
        collectFiles(
            in: directoryURL,
            baseDirectoryURL: directoryURL,
            includedExtensions: includedExtensions,
            includedFileNames: includedFileNames,
            excludedDirectoryNames: excludedDirectoryNames,
            into: &entries
        )

        guard !entries.isEmpty else { return nil }

        // 경로 기준 결정론적 오름차순 정렬
        entries.sort { $0.relativePath < $1.relativePath }

        #if canImport(CryptoKit)
        var outer = SHA256()
        for entry in entries {
            let recordLine = "\(entry.relativePath):\(entry.hash)\n"
            if let lineData = recordLine.data(using: .utf8) {
                outer.update(data: lineData)
            }
        }
        return outer.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        return nil
        #endif
    }

    /// 편의 오버로드: 디렉터리 경로(String)로 해시 계산
    public static func computeHash(
        forDirectoryPath path: String,
        includedExtensions: Set<String> = defaultSourceExtensions,
        includedFileNames: Set<String> = defaultSourceFileNames,
        excludedDirectoryNames: Set<String> = defaultExcludedDirectories
    ) -> String? {
        computeHash(
            for: URL(fileURLWithPath: path, isDirectory: true),
            includedExtensions: includedExtensions,
            includedFileNames: includedFileNames,
            excludedDirectoryNames: excludedDirectoryNames
        )
    }

    // MARK: - Private File Collection

    private static func collectFiles(
        in currentURL: URL,
        baseDirectoryURL: URL,
        includedExtensions: Set<String>,
        includedFileNames: Set<String>,
        excludedDirectoryNames: Set<String>,
        into entries: inout [(relativePath: String, hash: String)]
    ) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: currentURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { return }

        for itemURL in contents {
            let itemName = itemURL.lastPathComponent

            // 심볼릭 링크 디렉터리는 순환 방지를 위해 제외
            let isSymlink = (try? itemURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            guard !isSymlink else { continue }

            let isDirectory = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                guard !excludedDirectoryNames.contains(itemName) else { continue }
                collectFiles(
                    in: itemURL,
                    baseDirectoryURL: baseDirectoryURL,
                    includedExtensions: includedExtensions,
                    includedFileNames: includedFileNames,
                    excludedDirectoryNames: excludedDirectoryNames,
                    into: &entries
                )
                continue
            }

            let ext = itemURL.pathExtension.lowercased()
            let isNamed = includedFileNames.contains(itemName)
            let hasValidExt = !ext.isEmpty && includedExtensions.contains(ext)
            let isTarget = isNamed || hasValidExt
            guard isTarget else { continue }

            guard let fileData = try? Data(contentsOf: itemURL) else { continue }
            let hash = sha256Hex(fileData)

            let basePath = baseDirectoryURL.path
            let filePath = itemURL.path
            var relPath = filePath
            if relPath.hasPrefix(basePath) {
                relPath = String(relPath.dropFirst(basePath.count))
            }
            while relPath.hasPrefix("/") {
                relPath.removeFirst()
            }
            entries.append((relativePath: relPath, hash: hash))
        }
    }
}
