#if GujoManaged
import EndpointRouterKit
import Foundation
import GujoCoreKit
import InstallHealthKit
import InteropKit
import KeychainKit
#if canImport(AppKit)
import AppKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

public typealias GujoManagedStatus = GujoCoreKit.GujoManagedStatus
public typealias SignedEntitlementToken = GujoCoreKit.SignedEntitlementToken

public enum GujoManaged {
    /// Cloud Apps CLI 이름. dual-entry 규약상 PATH 에 설치된다.
    public static let cliName = "gujo-cloud-apps"

    /// 설치본 번들 ID. 경로 문자열을 상수로 박지 않는다 — dual-entry Helpers
    /// (`…/Foo.app/Contents/Helpers/cli`) 나 다른 볼륨의 /Applications 가 있다.
    public static let cloudAppsBundleIDs: [String] = [
        "net.ranode.gujo-cloud-apps",
        "kr.gujo.gujo-cloud-apps",
    ]

    /// CLI 심링크를 풀고 감싸는 `.app` 을 찾는다. 없으면 Launch Services, 그다음
    /// `/Applications` 에서 번들 ID 로 고른다.
    public static var appPath: String? { locateCloudAppsBundle() }

    public static func isInstalled(fm: FileManager = .default) -> Bool {
        if let path = appPath, fm.fileExists(atPath: path) { return true }
        return which(cliName) != nil
    }

    /// 마지막으로 확인된 상태 — 서명 토큰(`SignedEntitlementToken`) 검증 기반.
    /// 기존 UserDefaults 평문 대신, 암호 서명과 TTL 30일(철회기간 24h grace period)을 검증한다.
    public static var lastKnown: GujoManagedStatus? {
        lastKnown(bundleID: Bundle.main.bundleIdentifier, at: Date())
    }

    public static func lastKnown(
        bundleID: String?,
        at date: Date = Date(),
        publicKey: String = SignedEntitlementToken.defaultPublicKey
    ) -> GujoManagedStatus? {
        GujoManagedTokenStore.lastKnown(bundleID: bundleID, at: date, publicKey: publicKey)
    }

    public static let tokenCacheKey = GujoManagedTokenStore.tokenCacheKey

    public static func storeToken(_ token: SignedEntitlementToken, bundleID: String? = nil) {
        GujoManagedTokenStore.storeToken(token, bundleID: bundleID)
    }

    public static func loadStoredToken(
        bundleID: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> SignedEntitlementToken? {
        GujoManagedTokenStore.loadStoredToken(bundleID: bundleID, environment: environment)
    }

    /// `available` 판정을 이 시간만큼은 다시 CLI 에 안 묻는다. 매 실행마다 프로세스를
    /// 두 번 fork 하는 비용이 250개 앱 전체에서 누적되는 걸 막는다. `available` 이 아닌
    /// 상태(설치 필요·미연결·미구매)는 캐시하지 않고 매번 다시 물어 — 방금 로그인/구매한
    /// 사용자가 옛 캐시에 계속 막히면 안 된다.
    private static let freshWindow: TimeInterval = 6 * 60 * 60

    static func which(_ name: String) -> String? {
        for dir in [HostPlatform.homebrewBin, "/usr/local/bin", "/usr/bin"] {
            let p = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    static func decode(_ raw: String) -> GujoManagedStatus? {
        switch raw {
        case "cloudAppsMissing": return .cloudAppsMissing
        case "notConnected": return .notConnected
        case "notEntitled", "expired", "revoked", "blockedMinVersion": return .notEntitled
        case "available", "graceOffline": return .available
        default: return nil
        }
    }

    /// **앱이 넘기는 건 이것뿐이다.** slug 도, product id 도, 별도로 배정하는 값도
    /// 아니다 — 앱이 이미 갖고 있는 `CFBundleIdentifier` 하나. "레포 슬러그가 서버
    /// product 랑 다르다", "product id 를 어디서 배정하냐" 같은 매핑 문제는 전부
    /// Cloud Apps CLI(`gujo-cloud-apps entitlement --bundle-id`) **안에서** 끝난다.
    /// 의존성은 Cloud Apps 쪽에만 있어야 한다 — 소비 앱이 자기 정체성 이상을 알 필요는
    /// 없다.
    ///
    /// 라이선스 게이트는 퇴역했다. Cloud Apps 는 업데이트 원장만 맡는다.
    public static func status(
        bundleID: String? = Bundle.main.bundleIdentifier,
        now: Date = Date(),
        publicKey: String = SignedEntitlementToken.defaultPublicKey
    ) async -> GujoManagedStatus {
        _ = (bundleID, now, publicKey)
        return .available
    }

    /// 쓸 수 없을 때 **Cloud Apps 로 넘긴다**.
    ///
    /// 설치·연결·구매 화면을 앱마다 갖지 않는다 — 그러면 249개에 같은 UI 가 복제된다.
    /// 화면은 Cloud Apps 한 곳에만 있고, 소비 앱은 넘겨주기만 한다.
    ///
    /// 미설치면 열 것이 없으므로 다운로드 페이지를 연다.
    @MainActor
    public static func handOff(status: GujoManagedStatus) {
        #if canImport(AppKit)
        switch status {
        case .available:
            return
        case .cloudAppsMissing:
            if let url = URL(string: downloadURL) { NSWorkspace.shared.open(url) }
        case .notConnected, .notEntitled:
            if let path = appPath {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: .init())
            } else if let url = URL(string: downloadURL) {
                NSWorkspace.shared.open(url)
            }
        }
        #endif
    }

    // MARK: - CLI 진입점

    /// **부트스트랩 면제** — 게이트를 걸면 순환이 생기는 앱.
    ///
    /// Cloud Apps 는 원장 소유자라 자기를 막으면 아무도 판정을 못 받는다.
    /// 배포 관리자는 **Cloud Apps 를 설치하는 도구**다 — 막으면 Cloud Apps 가 없을 때
    /// 그걸 깔 수단이 사라진다. 경계는 여기까지다(결정 2026-08-05): 나머지는 승인
    /// 매니저를 포함해 전부 게이트한다. "이것도 운영 도구" 라는 이유로 목록을 늘리면
    /// 경계가 물러지고, 그러면 구조적 의존이 이름만 남는다.
    public static let bootstrapExemptBundleIDs: Set<String> = [
        "net.ranode.gujo-cloud-apps",
        "kr.gujo.gujo-cloud-apps",
        "net.ranode.appbuildmanager",
    ]

    /// PATH CLI → 실파일 → 감싸는 `.app`. dual-entry 정본.
    static func locateCloudAppsBundle(fm: FileManager = .default) -> String? {
        if let cli = which(cliName) {
            var url = URL(fileURLWithPath: cli).resolvingSymlinksInPath()
            while url.pathComponents.count > 1 {
                if url.pathExtension == "app" { return url.path }
                url.deleteLastPathComponent()
            }
        }
        #if canImport(AppKit)
        for id in cloudAppsBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                return url.path
            }
        }
        #endif
        let apps = "/Applications"
        do {
            let names = try fm.contentsOfDirectory(atPath: apps)
            for name in names where name.hasSuffix(".app") {
                let bundle = (apps as NSString).appendingPathComponent(name)
                let plist = (bundle as NSString).appendingPathComponent("Contents/Info.plist")
                guard let id = NSDictionary(contentsOfFile: plist)?["CFBundleIdentifier"] as? String,
                      cloudAppsBundleIDs.contains(id) else { continue }
                return bundle
            }
        } catch {
            return nil
        }
        return nil
    }

    /// dual-entry CLI 진입 한 줄. GUI 의 `.gujoManaged()` 와 대칭이다.
    ///
    /// **왜 CLI 도 막나**: `gujoManaged()` 는 `View` extension 이라 창만 막는다.
    /// 실측(2026-08-05) 관리되는 앱 130개 **전부** dual-entry CLI 를 갖고 있었고
    /// 그 CLI 는 원장에 묻지 않았다 — CLAUDE.md 가 "앱 고유 기능 제어는 소유 앱 CLI
    /// 우선" 이라고 못박은 바로 그 진입점이 게이트 밖이었다. 창만 막는 건 결제
    /// 게이트가 아니라 장식이다.
    ///
    /// **판정 실패는 통과시킨다** — GUI 와 같은 규칙이다. 못 물어본 것과 권한이 없는
    /// 것은 다르다. 이걸 섞으면 오프라인에서 CLI 가 죽어 자동화가 통째로 멈춘다.
    ///
    /// - Parameter allowing: 판정 없이 항상 통과시킬 서브커맨드. `help`·`version`·
    ///   `capabilities` 는 계약 조회라 막지 않는다 — 막으면 상호운용 레지스트리가
    ///   깨지고, 무엇이 왜 막혔는지조차 못 읽는다.
    /// **동기** 진입 — CLI `main.swift` 에 넣는 것은 이쪽이다.
    ///
    /// async 판을 top-level 에 넣으면 `main.swift` 전체가 async 컨텍스트가 되고,
    /// 그 순간 `Thread.sleep` 같은 `noasync` API 를 쓰던 앱이 컴파일에서 죽는다
    /// (실측 2026-08-05: `code-sign-helper-swift` — "class method 'sleep' is
    /// unavailable from asynchronous contexts"). 192개 CLI 에 심으면 그게 전부
    /// 시한폭탄이 된다. 프로세스 시작 시점에 잠깐 막는 건 문제가 아니므로
    /// 여기서 기다린다 — 파일의 async 여부를 바꾸지 않는 것이 훨씬 중요하다.
    public static func exitIfNotEntitledSync(
        arguments: [String] = Array(CommandLine.arguments.dropFirst()),
        allowing: Set<String> = ["help", "-h", "--help", "version", "-V", "--version",
                                 "capabilities"],
        bundleID: String? = Bundle.main.bundleIdentifier,
        code: Int32 = 77
    ) {
        // 낡은 설치본은 **옛 코드의 답**을 낸다. 이 저장소의 검사·연동은 대부분 설치본을
        // 부르므로 그 답이 조용히 사실로 굳는다 — 실측 2026-08-10: 낡은 감사기가 이미
        // 고쳐진 결함 16건을 계속 보고해 없는 문제를 다시 설계할 뻔했다.
        //
        // 이 한 줄이 **모든 CLI 의 첫 줄**이라(327앱 채택) 여기 붙이면 앱을 하나도
        // 고치지 않고 함대 전체가 자기 낡음을 말한다. help·version 처럼 위에서 곧장
        // 반환되는 경로보다 **먼저** 부른다 — `--help` 만 쳐도 낡은 건 알아야 한다.
        // 색인 파일 1회 읽기이고 stderr 한 줄이다(stdout=JSON 은 안 건드린다).
        StaleInstallIndex.warnIfStale()
        _ = arguments
        _ = allowing
        _ = bundleID
        _ = code
    }

    public static func exitIfNotEntitled(
        arguments: [String] = Array(CommandLine.arguments.dropFirst()),
        allowing: Set<String> = ["help", "-h", "--help", "version", "-V", "--version",
                                 "capabilities"],
        bundleID: String? = Bundle.main.bundleIdentifier,
        code: Int32 = 77
    ) async {
        _ = arguments
        _ = allowing
        _ = bundleID
        _ = code
    }

    /// CLI 는 창을 못 띄우니 **무엇을 하면 되는지 문장으로** 준다.
    static func message(for status: GujoManagedStatus) -> String {
        switch status {
        case .available:
            return ""
        case .cloudAppsMissing:
            return "Gujo Cloud Apps 설치가 필요합니다 — \(downloadURL)"
        case .notConnected:
            return "Gujo Cloud Apps 에 로그인해주세요 — open -a \"Gujo Cloud Apps\""
        case .notEntitled:
            return "Gujo Cloud Apps 에서 이 앱을 연결해주세요 — open -a \"Gujo Cloud Apps\""
        }
    }

    /// Cloud Apps 가 없을 때 안내할 곳. 스토어가 배포 정본이다.
    public static var downloadURL: String {
        GujoManagedTokenStore.downloadURL
    }

    /// 소비 앱이 API 요청에 실을 Gujo 토큰.
    ///
    /// 앱은 토큰을 저장하지 않는다. 로그인·원장은 Cloud Apps / Device SSO 가 갖고,
    /// 여기는 요청 수명 동안만 읽는다. 우선순위:
    /// 1. `GUJO_DEVICE_TOKEN` · `GUJO_API_TOKEN` · `GUJO_SKILL_STORE_TOKEN` (로컬 정적 bearer)
    /// 2. `GUJO_TOKEN_FILE` 경로의 한 줄 (로컬 파일 폴백)
    /// 3. LicenseKit Device SSO Keychain (`ai.gujo.device-account`)
    public static func currentToken(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        for key in ["GUJO_DEVICE_TOKEN", "GUJO_API_TOKEN", "GUJO_SKILL_STORE_TOKEN"] {
            if let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !raw.isEmpty {
                return raw
            }
        }
        if let path = environment["GUJO_TOKEN_FILE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           let fromFile = tokenFromFile(path) {
            return fromFile
        }
        let raw = CachedKeychainStore(service: "ai.gujo.device-account")
            .string(account: "device-token-v1")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    static func tokenFromFile(_ path: String) -> String? {
        let expanded = (path as NSString).expandingTildeInPath
        guard let raw = try? String(contentsOfFile: expanded, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    @discardableResult
    static func remember(_ s: GujoManagedStatus) -> GujoManagedStatus {
        GujoManagedTokenStore.remember(s)
    }

    /// `available` 이 `freshWindow` 안에 확인됐거나 유효한 서명 토큰이 있으면 CLI 를 다시 fork 하지 않고 그대로 쓴다.
    public static func freshAvailableCache(
        bundleID: String? = nil,
        at now: Date = Date(),
        publicKey: String = SignedEntitlementToken.defaultPublicKey
    ) -> GujoManagedStatus? {
        GujoManagedTokenStore.freshAvailableCache(bundleID: bundleID, at: now, publicKey: publicKey)
    }

    static func run(_ path: String, _ args: [String]) async -> [String: Any]? {
        await GujoManagedProcessRunner.run(path, args)
    }

    /// `software list --json` 처럼 최상위가 배열인 응답용.
    static func runArray(_ path: String, _ args: [String]) async -> [[String: Any]]? {
        await GujoManagedProcessRunner.runArray(path, args)
    }

    static func runData(_ path: String, _ args: [String]) async -> Data? {
        await GujoManagedProcessRunner.runData(path, args)
    }

    static func encode(_ s: GujoManagedStatus) -> String {
        switch s {
        case .cloudAppsMissing: return "cloudAppsMissing"
        case .notConnected: return "notConnected"
        case .notEntitled: return "notEntitled"
        case .available: return "available"
        }
    }
}

#if canImport(SwiftUI)
extension View {
    /// **한 줄 채택.** 기존 진입부를 재작성하지 않고 루트 뷰 뒤에 이 한 줄만 붙이면 된다.
    ///
    /// `adopt()`(구버전, fire-and-forget)와 달리 이건 **실제로 막는다** — 판정이 끝나기
    /// 전이나 `.available` 이 아닐 때는 진짜 화면 대신 아무 것도 아닌 대기 화면을 보여주고
    /// Cloud Apps 로 넘긴다. 대기 화면은 앱마다 새로 만드는 게 아니라 이 패키지 안에
    /// **하나만** 있다 — 그래서 "화면은 Cloud Apps 한 곳에" 원칙이 소비 앱 쪽에서도
    /// 지켜진다(대기 화면은 제품 화면이 아니라 통로일 뿐).
    ///
    /// 최초 판정 전에는 `lastKnown`(직전 확인값)을 낙관적으로 쓴다 — 캐시가 없는 첫 실행만
    /// `available` 로 관대하게 열고, 재실행부터는 직전 판정이 그대로 적용된다.
    ///
    /// 파라미터가 없다 — 앱을 식별할 값은 `Bundle.main.bundleIdentifier` 하나뿐이고
    /// 그건 이미 앱이 갖고 있다. 무엇을 넘길지 고민할 필요도, 실수로 잘못된 슬러그를
    /// 넘길 위험도 없다.
    @MainActor
    public func gujoManaged() -> some View {
        self
    }
}

@MainActor
private struct GujoManagedGateView<Content: View>: View {
    let content: Content
    @State private var status: GujoManagedStatus
    @State private var resolved: Bool

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        let cached = GujoManaged.lastKnown
        _status = State(initialValue: cached ?? .available)
        _resolved = State(initialValue: cached != nil)
    }

    var body: some View {
        Group {
            if resolved && status == .available {
                content
            } else if !resolved {
                ProgressView()
                    .frame(minWidth: 280, minHeight: 160)
            } else {
                GujoManagedWaitingView(status: status)
            }
        }
        .task {
            let s = await GujoManaged.status()
            status = s
            resolved = true
            if s != .available { GujoManaged.handOff(status: s) }
        }
    }
}

/// **직판(Developer ID) 채널** 대기 화면. Cloud Apps 가 권한 원장이다.
/// App Store / Play / 사설 스토어 빌드에는 `.gujoManaged()` 를 쓰지 않는다 —
/// 그 채널은 StoreKit · Play Billing · 서명 라이선스가 정본이다.
/// 제품별 문구·브랜딩을 안 넣는다 — 넣기 시작하면 249개에 또 복제된다.
private struct GujoManagedWaitingView: View {
    let status: GujoManagedStatus

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Mac 직판 · Gujo Cloud Apps")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(minWidth: 280, minHeight: 160)
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        switch status {
        case .cloudAppsMissing: "Gujo Cloud Apps 설치가 필요합니다."
        case .notConnected: "Gujo Cloud Apps 에 로그인해주세요."
        case .notEntitled: "Gujo Cloud Apps 에서 이 앱을 연결해주세요."
        case .available: ""
        }
    }
}
#endif
#endif
