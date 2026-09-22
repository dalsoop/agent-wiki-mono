import Foundation

/// swift-app-mono 앱 발견·설치본 로케이팅의 **공용 원자 유틸**.
///
/// 두 "앱스토어" 앱(store · app-build-manager)이 각자 갖고 있던 3가지 저수준 로직을
/// 한 곳으로 모은다 — 갈라지면 "설치본을 못 찾음/딴 데를 뒤짐" 류 사고가 나기 때문이다.
/// 상위 개념(각자의 Entry·서명/설치 판정)은 앱에 남기고, 아래 원자 연산만 공유한다:
///
///  1. `monorepoRoot(...)` — 모노레포 루트(apps/ 포함) 찾기(여러 소스 순차 시도).
///  2. `installedBundlePath(bundleName:)` — /Applications·~/Applications 에서 설치본 .app 찾기.
///  3. `infoPlist(at:)` / `string(_:fromInfoPlistAt:)` — Info.plist 안전 읽기.
///  4. `isValidBundle(at:)` — 유효한 앱 번들인지 검증(Info.plist 파싱 + 실행 파일 실존).
public enum AppScan {
    // MARK: - 모노레포 루트

    /// 모노레포 루트를 찾는다. 우선순위(앞이 우선):
    ///  1. 명시 `start`
    ///  2. `SWIFT_APP_MONO` / `SWIFT_APP_MONO_ROOT` 환경변수 (호출자가 고른 트리)
    ///  3. **cwd** 에서 climb — ship/CLI 기본은 "서 있는 곳"
    ///  4. `SA_SOURCE_ROOT` (ship 자리 — GUI cwd=/ 일 때 UserDefaults main 보다 앞)
    ///  5. UserDefaults `repoRoot` (GUI 가 기억한 폴더)
    ///  6. Info.plist 봉인 경로 (이 바이너리를 만든 트리 — 최후 수단)
    ///  6. 실행 파일 위치 / 워크스페이스 fallback
    ///
    /// 2026-08-07: 예전 순서는 UserDefaults·SASource 가 cwd 보다 앞서, worktree 에서
    /// ship 해도 설치본/GUI 가 기억한 `main/` 으로 조용히 떨어졌다. **빌드 소스 =
    /// 작업 트리** 가 기본이어야 한다.
    public static func monorepoRoot(start: String? = nil,
                                    defaults: UserDefaults = .standard,
                                    bundle: Bundle = .main) -> String? {
        var candidates: [String] = []
        if let start { candidates.append(start) }
        let env = ProcessInfo.processInfo.environment
        for key in ["SWIFT_APP_MONO", "SWIFT_APP_MONO_ROOT"] {
            if let v = env[key], !v.isEmpty { candidates.append(v) }
        }
        // cwd 를 봉인 경로·UserDefaults 보다 앞 — "지금 있는 monorepo" 가 기본 빌드 소스.
        candidates.append(FileManager.default.currentDirectoryPath)
        // GUI cwd 는 / 라 climb 실패 → 예전에 저장한 main/ 으로 떨어진다.
        // ship 자리(`SA_SOURCE_ROOT`)가 있으면 그 트리를 기억된 main 보다 앞세운다.
        if let v = env["SA_SOURCE_ROOT"], !v.isEmpty { candidates.append(v) }
        if let v = defaults.string(forKey: "repoRoot") { candidates.append(v) }
        if let v = bundle.object(forInfoDictionaryKey: "RepoRoot") as? String { candidates.append(v) }
        // SASourceDirectory 는 apps/<app> — climb 이 monorepo 루트로 올린다. 최후 수단.
        if let v = bundle.object(forInfoDictionaryKey: "SASourceDirectory") as? String { candidates.append(v) }
        candidates.append((CommandLine.arguments.first as NSString?)?.deletingLastPathComponent ?? ".")
        candidates.append(contentsOf: fallbacks)

        for c in candidates {
            if let hit = climb(from: c) { return hit }
        }
        return nil
    }

    /// ship/CLI 전용: **cwd monorepo 를 최우선**. `--root`·명시 오버라이드 env 만 그 앞.
    /// UserDefaults·SASource 봉인은 쓰지 않는다 — GUI 기억/옛 설치본 스탬프로
    /// worktree ship 이 새지 않게.
    ///
    /// 2026-08-10: `SWIFT_APP_MONO` 는 셸(`~/.zshenv`)이 **정본 main 을 가리키는 편의
    /// 포인터**로 항상 export 한다. 이걸 cwd 보다 앞에 두면 어느 worktree 에서 ship 해도
    /// 무조건 `main/` 으로 끌려가, worktree ship 이 아예 불가능했다(백로그 44949B35).
    /// 오버라이드 **의도**를 담은 `SWIFT_APP_MONO_ROOT` 만 cwd 앞에 두고,
    /// 맨 `SWIFT_APP_MONO` 는 cwd 에서 monorepo 를 못 찾을 때의 fallback 으로 내린다.
    public static func monorepoRootForShip(
        explicitRoot: String? = nil,
        cwd: String = FileManager.default.currentDirectoryPath,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        var candidates: [String] = []
        if let explicitRoot, !explicitRoot.isEmpty { candidates.append(explicitRoot) }
        if let v = environment["SWIFT_APP_MONO_ROOT"], !v.isEmpty { candidates.append(v) }
        candidates.append(cwd)
        if let v = environment["SWIFT_APP_MONO"], !v.isEmpty { candidates.append(v) }
        for c in candidates {
            if let hit = climb(from: c) { return hit }
        }
        return nil
    }

    /// 유효한 모노레포 루트인지.
    /// bare 껍데기(`swift-app-mono/apps` 에 Package.swift 없는 잔재 3개)를 루트로 잡지 않도록
    /// `apps/*/Package.swift` 가 **하나 이상** 있어야 한다.
    public static func isMonorepoRoot(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        let fm = FileManager.default
        let apps = (path as NSString).appendingPathComponent("apps")
        guard fm.fileExists(atPath: apps, isDirectory: &isDir), isDir.boolValue else { return false }
        guard let names = try? fm.contentsOfDirectory(atPath: apps) else { return false }
        for name in names {
            if name.hasPrefix(".") { continue }
            let pkg = ((apps as NSString).appendingPathComponent(name) as NSString)
                .appendingPathComponent("Package.swift")
            if fm.fileExists(atPath: pkg) {
                return true
            }
        }
        return false
    }

    /// `path`(또는 그 조상)가 모노레포 루트면 반환. 최대 12단계 위로 올라간다.
    public static func climb(from path: String) -> String? {
        let candidates = [
            URL(fileURLWithPath: path).resolvingSymlinksInPath(),
            URL(fileURLWithPath: path)
        ]
        for startURL in candidates {
            var dir = startURL
            for _ in 0..<12 {
                if isMonorepoRoot(dir.path) { return dir.path }
                let parent = dir.deletingLastPathComponent()
                if parent.path == dir.path { break }
                dir = parent
            }
        }
        return nil
    }

    /// 사용자가 앱에서 지정한 루트를 저장(다음 실행에 재사용).
    public static func setMonorepoRoot(_ path: String, defaults: UserDefaults = .standard) {
        defaults.set(path, forKey: "repoRoot")
    }

    private static var fallbacks: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Documents/WORK/WORKSPACE/apps/swift-app-mono/.worktrees/main",
            "\(home)/Documents/WORK/WORKSPACE/apps/swift-app-mono/main"
        ]
    }

    // MARK: - 설치본 로케이팅

    /// 설치본 .app 을 찾을 루트들. 앱마다 install-app.sh 의 DEST_ROOT 관례가 달라 둘 다 뒤진다.
    public static var installSearchRoots: [String] {
        ["/Applications", "\(FileManager.default.homeDirectoryForCurrentUser.path)/Applications", "/System/Applications"]
    }

    /// 유효한 앱 번들인지 검증.
    /// 디렉터리 검사뿐만 아니라 `Contents/Info.plist` 파싱 가능 여부 및
    /// `Contents/MacOS/<executable>` 실행 파일 실존 여부를 확인하여 텅 빈 `.app` 폴더나 깨진 번들 오탐을 방어한다.
    public static func isValidBundle(at path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: resolved, isDirectory: &isDir), isDir.boolValue else { return false }
        let plistPath = (resolved as NSString).appendingPathComponent("Contents/Info.plist")
        guard let info = infoPlist(at: plistPath) else { return false }
        guard let exeName = info["CFBundleExecutable"] as? String, !exeName.isEmpty else { return false }
        let exePath = ((resolved as NSString).appendingPathComponent("Contents/MacOS") as NSString).appendingPathComponent(exeName)
        var exeIsDir: ObjCBool = false
        guard fm.fileExists(atPath: exePath, isDirectory: &exeIsDir), !exeIsDir.boolValue else { return false }
        return true
    }

    /// 번들 이름(들)로 설치본 후보 전부. 순서: 각 `installSearchRoots` 직하 → 3-depth 중첩
    /// (`~/Applications/Gujo/Foo/Bar.app` 등). `/Applications` 가 앞 → 정본 우선.
    /// 중복 경로는 제거(심링크 해석). ExtraBundleRetire / install-macos-app.sh 잔재 퇴역과 정렬.
    public static func installedBundleCandidates(bundleNames: [String]) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        var seen = Set<String>()

        func appendIfApp(_ path: String) {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard isValidBundle(at: resolved) else { return }
            guard seen.insert(resolved).inserted else { return }
            out.append(resolved)
        }

        var seenDirs = Set<String>()

        for root in installSearchRoots {
            let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
            guard fm.fileExists(atPath: resolvedRoot) else { continue }

            for name in bundleNames {
                appendIfApp((resolvedRoot as NSString).appendingPathComponent("\(name).app"))
            }

            // 중첩 탐색: 3-depth 까지 본다.
            // 1-depth 만 보던 판은 그룹 폴더 아래 앱별 폴더가 한 겹 더 있는 실제 배치를 놓쳤다
            // (~/Applications/Gujo/161-app-build-manager/AppBuildManager.app 등).
            // 3-depth 로 일원화하여 깊은 중첩 구조의 설치본도 안정적으로 탐색한다.
            func scanChildren(of directory: String, depth: Int) {
                guard depth > 0 else { return }
                let resolvedDir = URL(fileURLWithPath: directory).resolvingSymlinksInPath().path
                guard seenDirs.insert(resolvedDir).inserted else { return }
                guard let kids = try? fm.contentsOfDirectory(atPath: resolvedDir) else { return }
                for kid in kids {
                    if kid.hasSuffix(".app") { continue }
                    if kid.contains(".retired-") || kid.contains(".fuse-era-retired") { continue }
                    if kid.hasPrefix(".") { continue }
                    let sub = (resolvedDir as NSString).appendingPathComponent(kid)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: sub, isDirectory: &isDir), isDir.boolValue else { continue }
                    for name in bundleNames {
                        appendIfApp((sub as NSString).appendingPathComponent("\(name).app"))
                    }
                    scanChildren(of: sub, depth: depth - 1)
                }
            }
            scanChildren(of: resolvedRoot, depth: 3)
        }
        return out
    }

    /// 번들 이름(들)로 설치본 .app 경로를 찾는다(없으면 nil). 정본 = candidates 첫 항목.
    public static func installedBundlePath(bundleNames: [String]) -> String? {
        installedBundleCandidates(bundleNames: bundleNames).first
    }

    /// 단일 번들 이름 편의 오버로드.
    public static func installedBundlePath(bundleName: String) -> String? {
        installedBundlePath(bundleNames: [bundleName])
    }

    /// 단일 이름 후보 목록 편의 오버로드.
    public static func installedBundleCandidates(bundleName: String) -> [String] {
        installedBundleCandidates(bundleNames: [bundleName])
    }

    // MARK: - Info.plist 읽기

    /// Info.plist 를 딕셔너리로 읽는다(실패 시 nil).
    public static func infoPlist(at path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict
    }

    /// Info.plist 에서 문자열 키 하나를 읽는다.
    public static func string(_ key: String, fromInfoPlistAt path: String) -> String? {
        infoPlist(at: path)?[key] as? String
    }
}
