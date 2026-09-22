import XCTest
@testable import LocalizationKit

final class ResourceBundleTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResBundleTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func makeBundle(
        _ name: String, withLproj: Bool, shallow: Bool = false, ext: String = "bundle"
    ) throws -> URL {
        let b = tmp.appendingPathComponent("\(name).\(ext)", isDirectory: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        if withLproj {
            // shallow = macOS 번들 레이아웃(유니버설 빌드 산출물): Contents/Resources/en.lproj
            let parent = shallow ? b.appendingPathComponent("Contents/Resources", isDirectory: true) : b
            let lproj = parent.appendingPathComponent("en.lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try "\"k\" = \"v\";".write(to: lproj.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        }
        return b
    }

    func testResolveNamedFindsExisting() throws {
        _ = try makeBundle("App_App", withLproj: true)
        let hit = ResourceBundle.resolveNamed("App_App", roots: [tmp])
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.bundleURL.lastPathComponent, "App_App.bundle")
    }

    func testResolveNamedMissingReturnsNil() {
        XCTAssertNil(ResourceBundle.resolveNamed("Nope", roots: [tmp]))
    }

    func testLocalizationAutodiscoversLprojBundle() throws {
        // lproj 없는 의존성 번들은 무시, lproj 있는 것만 채택.
        _ = try makeBundle("swift-nio_NIOPosix", withLproj: false)
        _ = try makeBundle("App_App", withLproj: true)
        let hit = ResourceBundle.resolveLocalization(preferredName: nil, roots: [tmp])
        XCTAssertEqual(hit?.bundleURL.lastPathComponent, "App_App.bundle")
    }

    func testLocalizationAutodiscoversShallowMacOSLayoutBundle() throws {
        // 유니버설(--arch x2) 빌드 산출물: .lproj 가 Contents/Resources/ 아래에 놓인다.
        // 최상위만 검사하던 회귀 — 설치본에서 전 키가 raw 로 노출됐다.
        _ = try makeBundle("App_App", withLproj: true, shallow: true)
        let hit = ResourceBundle.resolveLocalization(preferredName: nil, roots: [tmp])
        XCTAssertEqual(hit?.bundleURL.lastPathComponent, "App_App.bundle")
    }

    func testLocalizationPreferredNameWins() throws {
        _ = try makeBundle("Other_Other", withLproj: true)
        _ = try makeBundle("App_App", withLproj: true)
        let hit = ResourceBundle.resolveLocalization(preferredName: "App_App", roots: [tmp])
        XCTAssertEqual(hit?.bundleURL.lastPathComponent, "App_App.bundle")
    }

    func testLocalizationNoneReturnsNilThenFallback() {
        XCTAssertNil(ResourceBundle.resolveLocalization(preferredName: nil, roots: [tmp]))
        // public API 는 fallback 을 돌려준다(크래시 없음).
        let fallback = Bundle(for: ResourceBundleTests.self)
        let resolved = ResourceBundle.localization(preferredName: "Missing", fallback: fallback)
        XCTAssertNotNil(resolved)
    }

    func testLocalizationResolvesThroughSymlinkedRoot() throws {
        // `swift build` 산출 경로 `.build/debug` 는 심볼릭 링크 — contentsOfDirectory 가
        // 링크 URL 을 "Not a directory" 로 거부해 전 키가 raw 노출되던 회귀(TokenBar r0-B).
        _ = try makeBundle("App_App", withLproj: true)
        let link = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResBundleLink-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: tmp)
        defer { try? FileManager.default.removeItem(at: link) }
        // resourceRoots 가 만들어주는 형태와 동일하게 (원본 링크, 링크 해석본) 쌍으로 검증.
        let roots = [link, link.resolvingSymlinksInPath()]
        let hit = ResourceBundle.resolveLocalization(preferredName: nil, roots: roots)
        XCTAssertEqual(hit?.bundleURL.lastPathComponent, "App_App.bundle")
    }

    func testResourceRootsIncludesContentsResources() {
        let roots = ResourceBundle.resourceRoots()
        XCTAssertFalse(roots.isEmpty)
    }

    // MARK: - URL 축 (Bundle(url:) 이 빈손인 플랫폼)

    func testLocalizationRootPointsAtLprojDirectory() throws {
        let b = try makeBundle("App_App", withLproj: true)
        let root = ResourceBundle.resolveLocalizationRoot(preferredName: nil, roots: [tmp])
        XCTAssertEqual(root?.standardizedFileURL, b.standardizedFileURL,
                       "평면 레이아웃은 번들 최상위가 곧 lproj 디렉터리다")
    }

    func testLocalizationRootDescendsIntoShallowMacOSLayout() throws {
        let b = try makeBundle("App_App", withLproj: true, shallow: true)
        let root = ResourceBundle.resolveLocalizationRoot(preferredName: nil, roots: [tmp])
        XCTAssertEqual(root?.standardizedFileURL,
                       b.appendingPathComponent("Contents/Resources", isDirectory: true).standardizedFileURL)
    }

    /// 번들 축과 **같은 순위**여야 한다 — 두 길이 다른 번들을 고르면 폴백이 거짓말을 한다.
    func testLocalizationRootPrefersAppBundleOverDependencyKit() throws {
        _ = try makeBundle("swiftkit_VPNKit", withLproj: true)
        let app = try makeBundle("App_App", withLproj: true)
        let root = ResourceBundle.resolveLocalizationRoot(preferredName: nil, roots: [tmp], appName: "App")
        XCTAssertEqual(root?.standardizedFileURL, app.standardizedFileURL)
    }

    func testLocalizationRootMissingReturnsNil() throws {
        _ = try makeBundle("App_App", withLproj: false)
        XCTAssertNil(ResourceBundle.resolveLocalizationRoot(preferredName: nil, roots: [tmp]))
    }

    // MARK: - 리눅스 확장자 축 (`.resources`)

    /// SwiftPM 은 다윈에서 `<Pkg>_<Target>.bundle`, **리눅스에서 `.resources`** 를 낸다.
    /// 함대 코드가 `.bundle` 만 보고 있어 리눅스 CI 의 게이트가 전 줄을 키로 냈다
    /// (2026-09-04 잡 231691). 이름으로 찾는 축이 두 확장자를 다 봐야 한다.
    func testResolveNamedFindsLinuxResourcesExtension() throws {
        let made = try makeBundle("Pkg_Target", withLproj: true, ext: "resources")
        XCTAssertEqual(
            ResourceBundle.resolveNamedURL("Pkg_Target", roots: [tmp])?.standardizedFileURL,
            made.standardizedFileURL,
            ".resources 를 못 보면 리눅스에서 번들이 옆에 있어도 못 찾는다")
    }

    /// 이름을 모를 때 훑는 축도 마찬가지다.
    func testLocalizationRootFindsLinuxResourcesExtension() throws {
        let b = try makeBundle("Pkg_Target", withLproj: true, ext: "resources")
        let root = ResourceBundle.resolveLocalizationRoot(
            preferredName: nil, roots: [tmp], appName: "pkg")
        XCTAssertEqual(root?.standardizedFileURL, b.standardizedFileURL,
                       ".resources 도 평면 레이아웃이다 — 번들 최상위가 곧 lproj 디렉터리")
    }

    /// 다윈 확장자를 잃지 않는다 — 리눅스를 받느라 macOS 를 깨면 안 된다.
    func testDarwinBundleExtensionStillResolves() throws {
        let made = try makeBundle("Pkg_Target", withLproj: true)
        XCTAssertEqual(
            ResourceBundle.resolveNamedURL("Pkg_Target", roots: [tmp])?.standardizedFileURL,
            made.standardizedFileURL,
            "다윈 `.bundle` 도 같은 경로로 해석돼야 한다")
    }

    // MARK: - 실행 파일 디렉터리 축

    /// `.build/release` 는 `<triple>/release` 로 가는 심링크다. 원본과 해석본이
    /// 갈리면 **둘 다** 후보여야 한다 — 어느 쪽에 번들이 보이는지는 플랫폼이 정한다.
    func testExecutableDirectoryRootsCoversBothSidesOfASymlink() throws {
        let real = tmp.appendingPathComponent("x86_64/release", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = tmp.appendingPathComponent("release", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let roots = ResourceBundle.executableDirectoryRoots(
            execURL: link.appendingPathComponent("agent-lint-catalog"))

        XCTAssertEqual(roots.count, 2)
        XCTAssertEqual(roots.first?.standardizedFileURL, link.standardizedFileURL)
        XCTAssertEqual(roots.last?.standardizedFileURL, real.standardizedFileURL)
    }

    /// 심링크가 없으면 같은 자리를 두 번 넣지 않는다.
    func testExecutableDirectoryRootsDeduplicatesWhenNoSymlink() {
        let roots = ResourceBundle.executableDirectoryRoots(
            execURL: tmp.appendingPathComponent("cli"))
        XCTAssertEqual(roots.map(\.standardizedFileURL), [tmp.standardizedFileURL])
    }

    /// 실행 파일 디렉터리를 **앞세우지 않는다**. 앞세우면 PATH 심링크 실행에서 남의
    /// SPM 번들이 깔린 `/opt/homebrew/bin` 을 먼저 집는다(2026-08-22 실측).
    /// 두 축이 같은 자리를 가리키면 중복 제거로 한 칸이 되니 같아도 통과다.
    func testExecutableDirectoryRootIsNotAheadOfBundleAxis() {
        let paths = ResourceBundle.resourceRoots().map(\.standardizedFileURL)
        guard let exec = Bundle.main.executableURL,
              let execIndex = paths.firstIndex(of: exec.deletingLastPathComponent().standardizedFileURL),
              let bundleIndex = paths.firstIndex(of: Bundle.main.bundleURL.standardizedFileURL)
        else { return }
        XCTAssertLessThanOrEqual(bundleIndex, execIndex,
                                 "번들 축 후보가 실행 파일 디렉터리보다 앞이거나 같은 자리다")
    }
}
