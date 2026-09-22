import Foundation

/// 앱 하나의 공용 스캐폴드(`RanodeApp`) 채택 상태.
///
/// 이 함대는 횡단 관심사(기동 가드·라이선스 게이트·About 설정)를 앱마다 복붙해 왔고,
/// 그래서 채택률이 200/175/145/63 으로 흩어졌다(2026-08-04 실측). `AppScaffoldKit` 이
/// 그 반복을 끝내지만, **누가 아직 옛 방식인지**를 사람이 grep 으로 세면 같은 일이 반복된다.
/// 그래서 이 스캐너가 세게 한다.
///
/// 정본은 여기(AppScaffoldKit)다 — DistributionCore 의 ship GujoManaged 게이트도 이
/// 타입을 쓴다. swift-library-kit-manager-swift 의 동명 타입은 그 앱 지표 뷰의 사본이며
/// 점진적으로 이쪽을 import 하게 통합한다(백로그 참조).
public struct ScaffoldAdoption: Sendable, Equatable, Identifiable {
    public var id: String { app }
    public let app: String
    /// `AppScaffoldKit` 을 Package 의존으로 선언했나.
    public let hasScaffoldDependency: Bool
    /// `: RanodeApp` 을 실제로 채택했나.
    public let conformsToScaffold: Bool
    /// 아직 앱 안에 남아 있는 옛 복붙 흔적(전환하면 사라져야 하는 것들).
    public let legacySignals: [String]
    /// GUI 앱인가(`@main` + App/Delegate). 아니면 전환 대상이 아니다.
    public let isGUIApp: Bool
    /// AppDelegate 형태 — 프로토콜을 못 쓰므로 별도 경로가 필요하다.
    public let isAppDelegateStyle: Bool
    /// `.gujoManaged()` 한 줄 채택(2026-08-04 신설) — 전면 스캐폴드 전환 없이도
    /// 완료로 친다. 이걸 안 보면 한 줄 채택한 앱이 전부 "미전환"으로 잘못 잡힌다.
    public let isOneLineAdopted: Bool
    /// 대상이 아닌 앱(iOS 전용 · Cloud Apps 자기 자신) — 집계에서 뺀다.
    public let isExcluded: Bool
    /// `@main`이 여러 개거나 GUI 진입부를 하나로 특정 못하는 앱 — 자동화 대상 아님,
    /// 사람이 봐야 한다.
    public let isAmbiguousEntry: Bool

    public init(
        app: String, hasScaffoldDependency: Bool, conformsToScaffold: Bool,
        legacySignals: [String], isGUIApp: Bool, isAppDelegateStyle: Bool,
        isOneLineAdopted: Bool = false, isExcluded: Bool = false, isAmbiguousEntry: Bool = false
    ) {
        self.app = app
        self.hasScaffoldDependency = hasScaffoldDependency
        self.conformsToScaffold = conformsToScaffold
        self.legacySignals = legacySignals
        self.isGUIApp = isGUIApp
        self.isAppDelegateStyle = isAppDelegateStyle
        self.isOneLineAdopted = isOneLineAdopted
        self.isExcluded = isExcluded
        self.isAmbiguousEntry = isAmbiguousEntry
    }

    /// 전환 완료 = (전면 스캐폴드 채택 + 옛 흔적 없음) 또는 한 줄 채택.
    /// 의존만 걸고 채택은 안 한 상태(stale)를 완료로 세지 않는다 —
    /// 그게 바로 라이선스에서 32앱이 조용히 빠져 있던 형태다.
    public var isMigrated: Bool {
        let fullyScaffolded = conformsToScaffold && legacySignals.isEmpty
        return fullyScaffolded || isOneLineAdopted
    }

    /// 전환 대상인데 아직 안 된 앱. 제외 대상·애매한 진입부는 빼고 센다.
    public var needsMigration: Bool {
        isGUIApp && !isAppDelegateStyle && !isMigrated && !isExcluded && !isAmbiguousEntry
    }
}

public struct ScaffoldReport: Sendable, Equatable {
    public let apps: [ScaffoldAdoption]

    public init(apps: [ScaffoldAdoption]) { self.apps = apps }

    public var migrated: [ScaffoldAdoption] { apps.filter(\.isMigrated).sorted { $0.app < $1.app } }
    public var pending: [ScaffoldAdoption] { apps.filter(\.needsMigration).sorted { $0.app < $1.app } }
    /// 프로토콜을 못 쓰는 형태 — 별도 경로 필요.
    public var appDelegateStyle: [ScaffoldAdoption] {
        apps.filter { $0.isGUIApp && $0.isAppDelegateStyle && !$0.isMigrated }
            .sorted { $0.app < $1.app }
    }
    /// 집계 대상이 아닌 앱(iOS 전용 · Cloud Apps 자기 자신).
    public var excluded: [ScaffoldAdoption] { apps.filter(\.isExcluded).sorted { $0.app < $1.app } }
    /// 진입부를 자동으로 못 짚어서 사람이 봐야 하는 앱.
    public var ambiguousEntry: [ScaffoldAdoption] {
        apps.filter { $0.isGUIApp && $0.isAmbiguousEntry && !$0.isExcluded }
            .sorted { $0.app < $1.app }
    }
}

/// 함대의 공용 스캐폴드 채택 스캐너.
public enum ScaffoldAnalyzer {
    public static let scaffoldKit = "AppScaffoldKit"
    public static let scaffoldPackage = "swiftkit-appscaffold"

    /// 스캐폴드 프로토콜 목록. **여기 한 곳**에서 관리한다 —
    /// 새 프로토콜을 추가하고 이 목록을 안 고치면 그 앱들이 지표에서 통째로 사라진다
    /// (실측으로 두 번 겪었다: RanodeMenuBarApp · RanodeWindowGroupApp).
    public static let protocols = [
        "RanodeApp", "RanodeMenuBarApp", "RanodeWindowGroupApp",
        "RanodeMenuBarWindowGroupApp", "RanodeMenuBarExtraApp",
    ]

    /// 전환하면 사라져야 하는 옛 복붙 패턴. 남아 있으면 "절반만 전환"이다.
    static let legacyPatterns: [(signal: String, needle: String)] = [
        ("dual-entry 가드 직접 호출", "DualEntryRules.exitIfMisusedFromIdentity"),
        ("단일 인스턴스 가드 직접 호출", "SingleInstance.exitIfAlreadyRunning"),
        ("앱 로컬 About 뷰", "struct StandardAboutSettingsView"),
        ("라이선스 게이트 직접 배선", "StandardLicenseManager.make"),
    ]

    /// 이 앱 자신 — 자기가 관리 주체라 자기를 게이트할 수 없다.
    public static let selfManagingApp = "gujo-cloud-apps-swift"

    public static func analyze(repoRoot: String, fm: FileManager = .default) -> ScaffoldReport {
        let appNames = listDirs(repoRoot + "/apps", fm: fm)
        let apps = appNames.map { app -> ScaffoldAdoption in
            let appDir = repoRoot + "/apps/" + app
            // 스캐폴드는 swiftkit 이 아니라 swiftkit-appscaffold 패키지에서 온다
            // (Sparkle 순환을 피하려 분리 — 그 패키지 주석 참고).
            let manifest =
                (try? String(contentsOfFile: appDir + "/Package.swift", encoding: .utf8)) ?? ""
            let blob = sourceBlob(appDir + "/Sources", fm: fm)
            // 전환된 앱은 `: App` 이 아니라 `: RanodeApp` / `: RanodeMenuBarApp` 이다.
            // 이걸 빠뜨리면 전환한 앱이 대상에서 통째로 사라진다 — 전환도 미전환도
            // 아닌 상태가 되어 지표가 조용히 틀린다(실측 사고 2026-08-04).
            let conforms = protocols.contains { blob.contains(": " + $0) }
            let isGUI: Bool
            if blob.contains("@main") {
                let hasAppOrDelegateProtocol =
                    conforms || blob.contains(": App") || blob.contains("NSApplicationDelegate")
                isGUI = hasAppOrDelegateProtocol
            } else {
                isGUI = false
            }
            // GUI 진입부(`@main` + `: App`)가 여러 개면 자동화가 어느 걸 고쳐야 할지
            // 못 정한다 — 사람이 봐야 하는 케이스로 분리한다(뭉뚱그려 "미전환"으로
            // 세면 실제 작업량을 부풀린다, 실측 2026-08-05).
            let appEntryCount = countAppEntries(blob)
            // iOS 전용 앱을 뺀다 — AppScaffoldKit 은 지금 AppKit/NSWorkspace 전제라
            // macOS 전용이다. 이름 접미사 `-ios` 만으론 부족했다(실측 2026-08-05:
            // clipboard-ios-capture-poc·star-map-swift 는 이름이 안 맞아 새고 있었다)
            // — platforms 선언에 `.iOS(` 는 있는데 `.macOS(` 는 없으면(멀티플랫폼 아님)
            // 진짜 iOS 전용으로 본다.
            let iosOnly = manifest.contains(".iOS(") && !manifest.contains(".macOS(")
            let isExcluded = app == selfManagingApp || app.hasSuffix("-ios") || iosOnly
            // "앱 로컬 About 뷰" 시그널은 conforms == false 일 때만 의미가 있다 — RanodeApp
            // 계열은 프로토콜상 `settingsView` 를 직접 정의해야 하고, 관례상 이름을
            // `StandardAboutSettingsView` 로 두는 앱(swift-app-router-swift 등)이 있다.
            // conforms == true 인데 이 이름을 썼다고 "미전환"으로 오판하지 않는다
            // (실측 2026-08-05).
            let legacySignals = legacyPatterns
                .filter { blob.contains($0.needle) }
                .filter { !(conforms && $0.signal == "앱 로컬 About 뷰") }
                .map(\.signal)
            return ScaffoldAdoption(
                app: app,
                hasScaffoldDependency: manifest.contains(scaffoldPackage),
                conformsToScaffold: conforms,
                legacySignals: legacySignals,
                isGUIApp: isGUI,
                // App 프로토콜 없이 AppDelegate 만으로 도는 앱.
                isAppDelegateStyle: isGUI && !conforms && !blob.contains(": App"),
                isOneLineAdopted: blob.contains(".gujoManaged(") || blob.contains("GujoManaged.status("),
                isExcluded: isExcluded,
                isAmbiguousEntry: appEntryCount != 1
            )
        }
        return ScaffoldReport(apps: apps)
    }

    /// `@main` 이 붙고 `: App` 프로토콜을 채택한 구조체 개수. 0 또는 2개 이상이면
    /// 자동화가 진입부를 하나로 못 짚는다.
    static func countAppEntries(_ blob: String) -> Int {
        do {
            // 정적 패턴이라 컴파일타임에 검증된 식 — 실패는 0개(미집계)로 처리해도 안전.
            let regex = try NSRegularExpression(
                pattern: #"@main\s*\n\s*(?:public\s+)?struct\s+\w+\s*:\s*(?:App|Ranode\w*App)\b"#
            )
            let range = NSRange(blob.startIndex..., in: blob)
            return regex.numberOfMatches(in: blob, range: range)
        } catch {
            return 0
        }
    }

    /// 앱 소스 전체를 한 덩어리로. 진입부가 어느 파일에 있는지 앱마다 달라서
    /// 파일명 규칙에 기대지 않는다(그 가정이 감사기를 틀리게 만들었다).
    static func sourceBlob(_ dir: String, fm: FileManager) -> String {
        guard let en = fm.enumerator(atPath: dir) else { return "" }
        var out = ""
        for case let path as String in en where path.hasSuffix(".swift") {
            out += (try? String(contentsOfFile: dir + "/" + path, encoding: .utf8)) ?? ""
            out += "\n"
        }
        return out
    }

    static func listDirs(_ dir: String, fm: FileManager) -> [String] {
        // apps/ 가 없는 루트(앱 워크트리 등)는 스캔 대상 0개와 같다 — 오류가 아니다.
        let items: [String]
        do {
            items = try fm.contentsOfDirectory(atPath: dir)
        } catch {
            return []
        }
        return items.filter { name in
            guard !name.hasPrefix(".") else { return false }
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: dir + "/" + name, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
    }
}
