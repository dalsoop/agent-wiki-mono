import Foundation

public enum AppIdentityLocator {
    /// 실행 파일 기준으로 `Contents/Info.plist` 를 찾고(Helpers 안 CLI 는 두 단계 위, PATH 심링크는 실경로 해석),
    /// 없으면 `Packaging/package-identity.json` 을 위로 올라가 찾는다.
    public static func locate(executable: URL?) -> AppIdentity? {
        guard let executable else { return nil }
        let resolved = resolveExecutable(executable)

        if let plistURL = contentsInfoPlist(executable: resolved),
           FileManager.default.fileExists(atPath: plistURL.path) {
            return AppIdentity.load(plistURL: plistURL, sourceURL: resolved)
        }

        return climbToPackaging(startingAt: resolved.deletingLastPathComponent())
    }

    public static func locate(appDirectory: URL) -> AppIdentity? {
        let fm = FileManager.default
        let contentsPlist = appDirectory.appendingPathComponent("Contents/Info.plist")
        if fm.fileExists(atPath: contentsPlist.path) {
            return AppIdentity.load(plistURL: contentsPlist, sourceURL: appDirectory)
        }
        let pkgIdentity = appDirectory.appendingPathComponent("Packaging/package-identity.json")
        let pkgPlist = appDirectory.appendingPathComponent("Packaging/Info.plist")
        let hasIdentity = fm.fileExists(atPath: pkgIdentity.path)
        let hasPlist = fm.fileExists(atPath: pkgPlist.path)
        guard hasIdentity || hasPlist else { return nil }
        return AppIdentity.load(
            plistURL: hasPlist ? pkgPlist : nil,
            identityURL: hasIdentity ? pkgIdentity : nil,
            sourceURL: appDirectory
        )
    }

    public static func resolveExecutable(_ url: URL) -> URL {
        url.resolvingSymlinksInPath()
    }

    public static func contentsInfoPlist(executable: URL) -> URL? {
        let dir = executable.deletingLastPathComponent()
        let folder = dir.lastPathComponent
        guard folder == "Helpers" || folder == "MacOS" else { return nil }
        return dir.deletingLastPathComponent().appendingPathComponent("Info.plist")
    }

    public static func packageIdentityURL(startingAt url: URL) -> URL? {
        var dir = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        let fm = FileManager.default
        for _ in 0..<24 {
            let candidate = dir.appendingPathComponent("Packaging/package-identity.json")
            if fm.fileExists(atPath: candidate.path) { return candidate }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    public static func packagingInfoPlistURL(startingAt url: URL) -> URL? {
        var dir = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        let fm = FileManager.default
        for _ in 0..<24 {
            let candidate = dir.appendingPathComponent("Packaging/Info.plist")
            if fm.fileExists(atPath: candidate.path) { return candidate }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    public static func climbToPackaging(startingAt startDir: URL) -> AppIdentity? {
        var dir = startDir
        let fm = FileManager.default
        for _ in 0..<24 {
            let pkgIdentity = dir.appendingPathComponent("Packaging/package-identity.json")
            let pkgPlist = dir.appendingPathComponent("Packaging/Info.plist")
            let hasIdentity = fm.fileExists(atPath: pkgIdentity.path)
            let hasPlist = fm.fileExists(atPath: pkgPlist.path)
            if hasIdentity || hasPlist {
                return AppIdentity.load(
                    plistURL: hasPlist ? pkgPlist : nil,
                    identityURL: hasIdentity ? pkgIdentity : nil,
                    sourceURL: startDir
                )
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }
}
