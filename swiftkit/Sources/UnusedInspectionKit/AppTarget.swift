import Foundation
import AppScanKit

/// 모노레포 내의 개별 앱 타깃 구조
public struct MonorepoAppTarget: Identifiable, Sendable, Codable, Hashable {
    public var id: String { slug }
    public let slug: String
    public let rootURL: URL
    public let packageSwiftURL: URL?
    public let sourceDirectories: [URL]
    public let testDirectories: [URL]
    public let resourceDirectories: [URL]

    public init(
        slug: String,
        rootURL: URL,
        packageSwiftURL: URL?,
        sourceDirectories: [URL],
        testDirectories: [URL],
        resourceDirectories: [URL]
    ) {
        self.slug = slug
        self.rootURL = rootURL
        self.packageSwiftURL = packageSwiftURL
        self.sourceDirectories = sourceDirectories
        self.testDirectories = testDirectories
        self.resourceDirectories = resourceDirectories
    }
}

/// 모노레포 내 앱들을 탐색하는 공용 스캐너 (OS 비종속)
public enum AppTargetScanner {
    /// 모노레포 루트 아래의 모든 앱을 탐색한다.
    public static func scanApps(monorepoRoot: URL? = nil) -> [MonorepoAppTarget] {
        let rootPath = monorepoRoot?.path ?? AppScan.monorepoRoot() ?? FileManager.default.currentDirectoryPath
        let appsDir = URL(fileURLWithPath: rootPath).appendingPathComponent("apps")

        guard let enumerator = FileManager.default.enumerator(
            at: appsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        var targets: [MonorepoAppTarget] = []

        for case let itemURL as URL in enumerator {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let slug = itemURL.lastPathComponent
            let packageSwift = itemURL.appendingPathComponent("Package.swift")
            let hasPackage = FileManager.default.fileExists(atPath: packageSwift.path)

            // Sources, Tests, Resources 수집
            var sourceDirs: [URL] = []
            var testDirs: [URL] = []
            var resourceDirs: [URL] = []

            let potentialSources = itemURL.appendingPathComponent("Sources")
            if FileManager.default.fileExists(atPath: potentialSources.path) {
                sourceDirs.append(potentialSources)
            }

            let potentialTests = itemURL.appendingPathComponent("Tests")
            if FileManager.default.fileExists(atPath: potentialTests.path) {
                testDirs.append(potentialTests)
            }

            // Resources 및 Assets 탐색
            collectResourceDirs(in: itemURL, result: &resourceDirs)

            targets.append(MonorepoAppTarget(
                slug: slug,
                rootURL: itemURL,
                packageSwiftURL: hasPackage ? packageSwift : nil,
                sourceDirectories: sourceDirs,
                testDirectories: testDirs,
                resourceDirectories: resourceDirs
            ))
        }

        return targets.sorted { $0.slug < $1.slug }
    }

    /// 특정 slug 의 앱 타깃 하나를 찾는다.
    public static func findApp(slug: String, monorepoRoot: URL? = nil) -> MonorepoAppTarget? {
        let all = scanApps(monorepoRoot: monorepoRoot)
        return all.first { $0.slug == slug }
    }

    private static func collectResourceDirs(in root: URL, result: inout [URL]) {
        let fileManager = FileManager.default
        guard let subEnumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let dirURL as URL in subEnumerator {
            let name = dirURL.lastPathComponent
            if name == ".build" || name == ".git" {
                subEnumerator.skipDescendants()
                continue
            }
            if name == "Resources" || name.hasSuffix(".xcassets") || name == "SampleAssets" || name == "Fixtures" {
                result.append(dirURL)
                subEnumerator.skipDescendants()
            }
        }
    }
}

/// 모노레포 내 타깃 앱 간이 모델 (인스펙터 공용)
public struct AppTarget: Identifiable, Sendable, Codable, Hashable {
    public var id: String { slug }
    public let name: String
    public let slug: String
    public let rootURL: URL

    public init(name: String, slug: String, rootURL: URL) {
        self.name = name
        self.slug = slug
        self.rootURL = rootURL
    }

    public static func discoverApps(in repoRoot: URL) -> [AppTarget] {
        let targets = AppTargetScanner.scanApps(monorepoRoot: repoRoot)
        return targets.map { target in
            AppTarget(name: target.slug, slug: target.slug, rootURL: target.rootURL)
        }
    }
}
