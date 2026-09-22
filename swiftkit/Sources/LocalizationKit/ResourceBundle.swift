import Foundation

/// SwiftPM 리소스 번들(예: `Mounter_Mounter.bundle`)을 **설치된 .app 에서도** 안전하게 찾는다.
///
/// 배경(함정): SwiftPM 이 실행 파일 타깃에 생성하는 `Bundle.module` 접근자는 리소스 번들을
/// 딱 두 곳에서만 찾는다 — (1) 앱 루트 `Bundle.main.bundleURL/<name>.bundle`, (2) 빌드 시각에
/// baked 된 절대 `.build/.../<name>.bundle` 경로. codesign 은 (1)(번들 루트의 미봉인 콘텐츠)을
/// 거부하므로 `make-app.sh` 는 번들을 `Contents/Resources/` 로 옮기는데, 접근자는 거길 보지 않아
/// 결국 (2)에만 의존한다. 그 baked 경로가 임시 worktree 라 삭제되면 `Bundle.module` 이 그 자리에서
/// `fatalError` 로 앱을 죽인다(설치본이 시작하자마자 크래시).
///
/// 이 리졸버는 **설치본의 정상 위치인 `Contents/Resources`(및 `swift run` 시 실행 파일 옆)** 를
/// 직접 뒤져 리소스 번들을 찾는다. 못 찾으면 `fatalError` 대신 `fallback`(기본 `.main`)을 돌려줘
/// 최소한 크래시는 막는다. `.build` baked 경로에 의존하지 않으므로 worktree 를 지워도 안전하다.
public enum ResourceBundle {
    /// `Bundle(for:)` 가 이 모듈이 링크된 번들을 가리키게 하는 앵커.
    private final class BundleFinder {}

    /// 후보 리소스 루트: 설치본 `Contents/Resources`, CLI/테스트 실행 파일 옆, 앱 루트.
    ///
    /// `swift test` 에선 `Bundle.main` 이 시스템 `xctest` 도구라 앱 리소스를 못 가리킨다. 반면
    /// `Bundle(for: BundleFinder.self)` 는 이 코드가 링크된 번들(테스트 시 `…/debug/*.xctest`)을
    /// 가리키므로, 그 옆 `…/debug/<Pkg>_<Target>.bundle`(상위 디렉터리)까지 후보에 넣는다.
    static func resourceRoots(main: Bundle = .main) -> [URL] {
        var roots: [URL] = []
        for bundle in [main, Bundle(for: BundleFinder.self)] {
            // Helpers CLI(dual-entry) 강신호를 **최우선**에 둔다. 비번들 실행 파일의
            // bundleURL 은 실행 파일이 아니라 포함 디렉터리다(실측 2026-08-22: 직접
            // 실행=Helpers/, PATH 심링크 실행=심링크의 디렉터리). 심링크 실행 시 그
            // 디렉터리가 /opt/homebrew/bin 처럼 **남의 SPM 번들이 깔린** 곳이면 리소스
            // 루트 후보에서 남의 번들이 먼저 채택돼 전 키가 raw 로 샜다. 실행 파일의
            // 심링크 해석본에서 뽑은 .app/Contents/Resources 후보는 실제 구조에서만
            // 존재하므로 앞세워도 오탐이 없다.
            if let exec = bundle.executableURL {
                roots.append(contentsOf: helpersAppResourceRootsResolving(cliURL: exec))
            }
            if let r = bundle.resourceURL { roots.append(r) }
            roots.append(bundle.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true))
            roots.append(bundle.bundleURL)
            // swift test/run: 실행 산출물(.xctest/실행파일) 옆에 리소스 번들이 형제로 놓인다.
            roots.append(bundle.bundleURL.deletingLastPathComponent())
            // bundleURL(디렉터리) 기반 후보 — 직접 실행(=Helpers/)의 한 칸 위가
            // Contents 인 경우. 위 executableURL 경로가 잡는 경우와 겹치면 중복 제거된다.
            roots.append(contentsOf: helpersAppResourceRootsResolving(cliURL: bundle.bundleURL))
        }
        // 마지막 후보: **실행 파일이 놓인 디렉터리** 자체.
        //
        // `swift build` 산출물(`.build/release/<cli>`) 옆에 리소스 번들이 형제로 놓이는데,
        // 이 자리를 `Bundle.main.bundleURL` 이 가리켜 주느냐는 플랫폼이 정한다 —
        // 리눅스 corelibs 에서 그 보장이 없다. 앞의 후보들이 다 빈손일 때만 닿도록
        // **맨 뒤**에 둔다: PATH 심링크 실행(`/opt/homebrew/bin`)에선 이 디렉터리에
        // 남의 SPM 번들이 깔려 있어(2026-08-22 실측) 앞세우면 그걸 먼저 집는다.
        for bundle in [main, Bundle(for: BundleFinder.self)] {
            guard let exec = bundle.executableURL else { continue }
            roots.append(contentsOf: executableDirectoryRoots(execURL: exec))
        }
        // `swift build` 의 `.build/debug` 는 `arm64-apple-macosx/debug` 로 가는 **심볼릭 링크**다.
        // `contentsOfDirectory(at:)` 가 심볼릭 링크 URL 을 POSIX 20(Not a directory)으로 거부해
        // loose 실행 산출물에서 전 키가 raw 로 노출됐다 — 링크 해석본도 후보에 넣는다.
        var seen = Set<String>()
        return roots
            .flatMap { [$0, $0.resolvingSymlinksInPath()] }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// 실행 파일이 놓인 디렉터리(원본 · 심링크 해석본). `.build/release` 처럼 경로에
    /// 심링크가 낀 자리에서 둘이 갈리므로 양쪽을 다 후보로 준다.
    static func executableDirectoryRoots(execURL: URL) -> [URL] {
        // **디렉터리**를 해석한다. 실행 파일까지 붙여 해석하면 그 파일이 아직 없는
        // 경우(시험·미빌드) 경로 전체가 미해석으로 돌아와 심링크가 안 풀린다.
        let direct = execURL.deletingLastPathComponent()
        let resolved = direct.resolvingSymlinksInPath()
        return direct.standardizedFileURL == resolved.standardizedFileURL
            ? [direct] : [direct, resolved]
    }

    /// Helpers CLI 실행 파일(.app/Contents/Helpers/<cli>)에서 앱 리소스 루트 후보.
    /// 실행 파일 자체가 번들 URL 이라 한 칸 위는 Helpers/, 두 칸 위는 Contents/ 다.
    /// 한 칸만 보면 Helpers/Resources 를 검사하고 앱 Resources 를 놓친다
    /// (2026-08-22 설치본 실측: 전 키가 raw 로 노출됐다).
    static func helpersAppResourceRoots(cliURL: URL) -> [URL] {
        let helpers = cliURL.deletingLastPathComponent()
        return [
            helpers.appendingPathComponent("Resources", isDirectory: true),
            helpers.deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true),
        ]
    }

    /// PATH 심링크(/opt/homebrew/bin/<cli> → .app/Contents/Helpers/<cli>)로 실행하면
    /// Bundle.main 이 심링크 경로에 붙는다 — 원본 URL 후보에는 앱이 없으므로
    /// 심링크 해석본에서도 후보를 뽑는다(2026-08-22 실측: 심링크 실행 시에만
    /// 전 키가 raw 로 샜다).
    static func helpersAppResourceRootsResolving(cliURL: URL) -> [URL] {
        var urls = helpersAppResourceRoots(cliURL: cliURL)
        let resolved = cliURL.resolvingSymlinksInPath()
        if resolved != cliURL {
            urls.append(contentsOf: helpersAppResourceRoots(cliURL: resolved))
        }
        return urls
    }

    /// `<name>.bundle`(리눅스는 `.resources`)을 루트들에서 찾는다. 테스트 가능한 순수 코어.
    static func resolveNamed(_ name: String, roots: [URL], fileManager fm: FileManager = .default) -> Bundle? {
        guard let url = resolveNamedURL(name, roots: roots, fileManager: fm) else { return nil }
        return Bundle(url: url)
    }

    /// SwiftPM 리소스 번들의 확장자 — **플랫폼마다 다르다.**
    ///
    /// 다윈은 `<Pkg>_<Target>.bundle`, 리눅스는 `<Pkg>_<Target>.resources` 다
    /// (SwiftPM 이 타깃별로 생성하는 `resource_bundle_accessor.swift` 가 그렇게 적는다).
    /// 함대 코드가 `.bundle` 만 보고 있어 리눅스 CI 에서는 번들이 **옆에 있는데도**
    /// 한 개도 안 잡혔다(2026-09-04 잡 231691: "l10n 번들 0개" — 그래서 전 줄이 키로 샜다).
    static let bundleExtensions = ["bundle", "resources"]

    /// 같은 탐색을 URL 로 돌려준다 — `Bundle(url:)` 을 거치지 않는 축이 쓴다.
    static func resolveNamedURL(_ name: String, roots: [URL], fileManager fm: FileManager = .default) -> URL? {
        for root in roots {
            for ext in bundleExtensions {
                let url = root.appendingPathComponent("\(name).\(ext)", isDirectory: true)
                if fm.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    /// preferredName 우선, 없으면 `.lproj` 를 포함한 첫 리소스 번들을 채택. 테스트 가능한 순수 코어.
    ///
    /// `.lproj` 는 번들 최상위(플랫 레이아웃, `swift build` 단일 아치) **또는**
    /// `Contents/Resources/`(macOS 셸로우 레이아웃, `--arch a --arch b` 유니버설 빌드) 에 놓인다.
    /// 최상위만 보면 유니버설 빌드로 패키징된 설치본에서 번들을 걸러버려 전 키가 raw 로 샌다.
    static func resolveLocalization(
        preferredName: String?,
        roots: [URL],
        appName: String? = mainAppName(),
        fileManager fm: FileManager = .default
    ) -> Bundle? {
        if let name = preferredName, let hit = resolveNamed(name, roots: roots, fileManager: fm) { return hit }
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            let bundles = items.filter { bundleExtensions.contains($0.pathExtension) }
            // 앱 자기 번들을 **의존성 번들보다 먼저** 본다.
            //
            // 함정(실측 2026-07-27, databaseviewer-swift): 설치본에 `.lproj` 를 가진 번들이
            // 둘 이상일 수 있다 — 앱의 `<Pkg>_<Target>.bundle` 과 `swiftkit_VPNKit.bundle`,
            // `KeyboardShortcuts_KeyboardShortcuts.bundle` 같은 SPM 의존성. 디렉터리 나열
            // 순서대로 집으면 의존성이 먼저 걸리고, 거기엔 앱 키가 없어 화면 문구가
            // `home.subtitle` 처럼 **키 그대로** 노출된다.
            //
            // "의존성 목록"을 관리하는 대신(끝이 없다) **앱 이름과 맞는 번들을 찾는다**.
            for item in bundles.sorted(by: { rank($0, appName: appName) < rank($1, appName: appName) }) {
                if containsLproj(item, fileManager: fm), let bundle = Bundle(url: item) {
                    return bundle
                }
            }
        }
        return nil
    }

    /// 실행 중인 앱 이름. SwiftPM 리소스 번들은 `<Package>_<Target>.bundle` 이라
    /// 실행 파일 이름·번들 이름 중 하나가 앞부분과 맞는다.
    static func mainAppName(main: Bundle = .main) -> String? {
        main.executableURL?.deletingPathExtension().lastPathComponent
            ?? main.bundleURL.deletingPathExtension().lastPathComponent
    }

    /// 낮을수록 먼저. 0 = 앱 이름과 맞음, 1 = 그 외, 2 = 알려진 의존성 kit.
    static func rank(_ url: URL, appName: String?) -> Int {
        let name = url.deletingPathExtension().lastPathComponent
        if let app = appName, !app.isEmpty {
            // `Mounter_Mounter`, `ScreenshotSwift_ScreenshotL10n` 처럼 패키지명이 앞에 온다.
            // CLI 실행 파일은 kebab(`tmp-l10n-probe`), SwiftPM 번들은 PascalCase
            // (`TmpL10nProbe_TmpL10nProbe.bundle`)라 대소문자·구분자를 접어서 비교한다.
            // 정확히 이 간극 때문에 lproj 를 든 Sparkle 의존성 번들(Help 도움말 현지화)이
            // 앱 번들보다 먼저 집혀 CLI 출력이 raw 키로 샜다(2026-08-22 실측).
            let fold: (String) -> String = {
                $0.replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .lowercased()
            }
            if fold(name).hasPrefix(fold(app) + "_") { return 0 }
        }
        return isDependencyKitBundle(url) ? 2 : 1
    }

    /// 앱이 아니라 의존성이 심은 리소스 번들로 보이는가. rank 0 이 없을 때의 마지막 기준.
    ///
    /// swiftkit 패밀리는 패키지명이 셋이다 — `swiftkit`, `swiftkit-appscaffold`,
    /// `swiftkit-sparkle`. 그중 sparkle 의 `SparkleUpdateKit.bundle` 은 자체 en/ko
    /// lproj 를 가지고 있어서(실측 2026-08-22, vscode-extension-runaway-monitor 테스트),
    /// `swiftkit_` 접두사만 보면 rank 동률로 앱 번들과 경합해 번들 채택을 가로챈다 —
    /// 전 키가 raw 로 노출되는 그 함정의 변형이다. 하이픈 변형까지 잡는다.
    static func isDependencyKitBundle(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        return ["swiftkit_", "swiftkit-", "KeyboardShortcuts_", "swift-crypto_", "Vortex_"]
            .contains { name.hasPrefix($0) }
    }

    /// 번들 최상위 또는 `Contents/Resources/` 에 `.lproj` 가 있는지 검사한다.
    private static func containsLproj(_ bundleURL: URL, fileManager fm: FileManager) -> Bool {
        lprojDirectory(bundleURL, fileManager: fm) != nil
    }

    /// `.lproj` 를 **담고 있는 디렉터리**를 돌려준다 — 번들 최상위(평면, `swift build`)
    /// 또는 `Contents/Resources/`(macOS 셸로우). 없으면 nil.
    static func lprojDirectory(_ bundleURL: URL, fileManager fm: FileManager = .default) -> URL? {
        let candidates = [
            bundleURL,
            bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true),
        ]
        for dir in candidates {
            guard let sub = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            if sub.contains(where: { $0.pathExtension == "lproj" }) { return dir }
        }
        return nil
    }

    /// `resolveLocalization` 과 **같은 순위**로 고르되 번들이 아니라 `.lproj` 디렉터리를
    /// 돌려준다. `Bundle(url:)` 이 빈손인 플랫폼(Linux 평면 번들)에서도 통하는 유일한 길이다.
    static func resolveLocalizationRoot(
        preferredName: String?,
        roots: [URL],
        appName: String? = mainAppName(),
        fileManager fm: FileManager = .default
    ) -> URL? {
        if let name = preferredName,
           let url = resolveNamedURL(name, roots: roots, fileManager: fm),
           let dir = lprojDirectory(url, fileManager: fm) { return dir }
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            let bundles = items.filter { bundleExtensions.contains($0.pathExtension) }
            for item in bundles.sorted(by: { rank($0, appName: appName) < rank($1, appName: appName) }) {
                if let dir = lprojDirectory(item, fileManager: fm) { return dir }
            }
        }
        return nil
    }

    /// 이름을 알 때: `<name>.bundle` 을 설치 위치에서 찾는다.
    public static func named(_ name: String, fallback: @autoclosure () -> Bundle = .main) -> Bundle {
        resolveNamed(name, roots: resourceRoots()) ?? fallback()
    }

    /// 이름을 몰라도 됨: `.lproj` 를 포함한 첫 `*.bundle` 을 로컬라이제이션 번들로 채택한다.
    /// (의존성 리소스 번들은 보통 `.lproj` 가 없어 자연히 걸러진다.) 앱 코드에서 `.module` 대신 쓴다.
    public static func localization(preferredName: String? = nil, fallback: @autoclosure () -> Bundle = .main) -> Bundle {
        resolveLocalization(preferredName: preferredName, roots: resourceRoots()) ?? fallback()
    }

    /// 같은 번들을 **파일로 읽는** 카탈로그로 돌려준다. 번들 API 가 빈손인 플랫폼의 폴백.
    public static func localizationCatalog(preferredName: String? = nil) -> LocalizationCatalog? {
        resolveLocalizationRoot(preferredName: preferredName, roots: resourceRoots())
            .map(LocalizationCatalog.init(root:))
    }
}
