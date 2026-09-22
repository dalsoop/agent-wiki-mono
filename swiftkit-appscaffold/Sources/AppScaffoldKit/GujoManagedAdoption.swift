import Foundation

/// 함대가 **Cloud Apps 에 실제로 물려 있는가**를 소스에서 읽는다.
///
/// `GujoManaged.swift` 가 런타임 판정(이 앱을 쓸 수 있나)이라면 여기는 채택 판정
/// (이 앱이 판정을 받기는 하나)이다. 둘을 같은 패키지에 두는 이유: 채택 규칙은
/// 시스템 자신의 일부라, 다른 앱이 복제해서 들고 있으면 정본이 갈라진다.
///
/// **`#if GujoManaged` 밖에 둔다.** 이걸 읽는 도구는 자기가 managed 인지와 무관하게
/// 함대를 봐야 한다 — trait 뒤에 숨기면 도구가 자기 자신을 못 본다.
public enum GujoManagedAdoption {
    /// 앱 하나가 시스템에 대해 갖는 상태.
    public enum State: String, Sendable, Codable, CaseIterable {
        /// trait 를 켜고 게이트도 부른다 — 목표 상태.
        case managed
        /// trait 만 켜고 게이트를 안 부른다. 배선은 끌어오고 관리는 안 받는다 —
        /// 겉보기엔 managed 인데 아니다. 컴파일이 안 깨져서 눈에 안 띈다.
        case traitOnly = "trait-only"
        /// 아무것도 안 했다.
        case notAdopted = "not-adopted"

        public var label: String {
            switch self {
            case .managed: "관리됨"
            case .traitOnly: "trait만"
            case .notAdopted: "미채택"
            }
        }
    }

    /// 앱 하나에서 읽은 **사실만**. 정책 판단(면제 여부)은 여기 없다 —
    /// 그건 `Policy` 가 따로 얹는다. 사실과 정책을 한 타입에 섞으면
    /// 정책이 바뀔 때 사실까지 다시 읽어야 한다.
    public struct AppRecord: Sendable, Codable, Equatable, Identifiable {
        public let directory: String
        public let traitEnabled: Bool
        public let callsGate: Bool
        /// dual-entry CLI 이름. 있으면 GUI 말고 **또 하나의 진입점**이 있다는 뜻이다.
        public let cliName: String?
        /// CLI 경로에서 판정을 부르는가. 현재 함대 실측 전부 false —
        /// `gujoManaged()` 가 `View` extension 이라 창만 막는다.
        public let cliConsultsLedger: Bool
        /// Package.swift 가 `LicenseKit` product 를 직접 의존한다.
        /// GujoManaged(Cloud Apps 권한) 과 병존하면 옛 키 경로 잔존 후보.
        public let dependsOnLicenseKit: Bool
        /// 앱 Sources 가 `import LicenseKit` 또는 키 활성화 API 를 코드로 부른다.
        public let usesLegacyLicenseAPI: Bool

        public var id: String { directory }

        public var state: State {
            if callsGate { return .managed }
            return traitEnabled ? .traitOnly : .notAdopted
        }

        /// GUI 는 막히는데 CLI 는 안 막히는가 — 구조적 의존의 구멍.
        public var hasUngatedCLI: Bool {
            state == .managed && cliName != nil && !cliConsultsLedger
        }

        /// Cloud Apps 게이트와 **별개로** 키 붙여넣기 라이선스 경로가 **소비 앱**에 잔존.
        ///
        /// 라이선스 인프라 앱(발급·지갑·스토어·배포)은 LicenseKit 이 본업이라
        /// "옛 경로 잔존" 으로 세지 않는다 — 그쪽이 키 원장이다.
        public var hasLegacyLicensePath: Bool {
            guard usesLegacyLicenseAPI || (dependsOnLicenseKit && traitEnabled) else {
                return false
            }
            return !GujoManagedAdoption.isLicenseKitKeeper(directory: directory)
        }

        /// 파생값도 **JSON 에 싣는다.** 안 실으면 소비자가 판정 규칙을 다시 구현한다.
        enum CodingKeys: String, CodingKey {
            case directory, traitEnabled, callsGate, cliName, cliConsultsLedger
            case dependsOnLicenseKit, usesLegacyLicenseAPI
            case state, hasUngatedCLI, hasLegacyLicensePath
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(directory, forKey: .directory)
            try c.encode(traitEnabled, forKey: .traitEnabled)
            try c.encode(callsGate, forKey: .callsGate)
            try c.encodeIfPresent(cliName, forKey: .cliName)
            try c.encode(cliConsultsLedger, forKey: .cliConsultsLedger)
            try c.encode(dependsOnLicenseKit, forKey: .dependsOnLicenseKit)
            try c.encode(usesLegacyLicenseAPI, forKey: .usesLegacyLicenseAPI)
            try c.encode(state, forKey: .state)
            try c.encode(hasUngatedCLI, forKey: .hasUngatedCLI)
            try c.encode(hasLegacyLicensePath, forKey: .hasLegacyLicensePath)
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            directory = try c.decode(String.self, forKey: .directory)
            traitEnabled = try c.decode(Bool.self, forKey: .traitEnabled)
            callsGate = try c.decode(Bool.self, forKey: .callsGate)
            cliName = try c.decodeIfPresent(String.self, forKey: .cliName)
            cliConsultsLedger = try c.decode(Bool.self, forKey: .cliConsultsLedger)
            dependsOnLicenseKit = try c.decodeIfPresent(Bool.self, forKey: .dependsOnLicenseKit) ?? false
            usesLegacyLicenseAPI = try c.decodeIfPresent(Bool.self, forKey: .usesLegacyLicenseAPI) ?? false
        }

        public init(
            directory: String, traitEnabled: Bool, callsGate: Bool,
            cliName: String?, cliConsultsLedger: Bool,
            dependsOnLicenseKit: Bool = false, usesLegacyLicenseAPI: Bool = false
        ) {
            self.directory = directory
            self.traitEnabled = traitEnabled
            self.callsGate = callsGate
            self.cliName = cliName
            self.cliConsultsLedger = cliConsultsLedger
            self.dependsOnLicenseKit = dependsOnLicenseKit
            self.usesLegacyLicenseAPI = usesLegacyLicenseAPI
        }
    }

    public struct Summary: Sendable, Codable, Equatable {
        public var total = 0
        public var managed = 0
        public var traitOnly = 0
        public var notAdopted = 0
        public var ungatedCLI = 0
        /// 옛 LicenseKit 키 경로 잔존(GujoManaged 와 병존).
        public var legacyLicensePath = 0

        public init() {}

        /// 통일화 진행률 — 분모는 **면제를 뺀** 대상 앱이다.
        public var adoptionRate: Double {
            total == 0 ? 0 : Double(managed) / Double(total)
        }
    }

    // MARK: - 스캔

    public static func scan(appsRoot: URL) -> [AppRecord] {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(
            at: appsRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries
            .filter(\.hasDirectoryPath)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { record(appDirectory: $0) }
    }

    /// 앱 하나를 읽는다. `Package.swift` 가 없으면 앱이 아니다(리소스 디렉터리 등).
    public static func record(appDirectory: URL) -> AppRecord? {
        let manifest = appDirectory.appendingPathComponent("Package.swift")
        guard let package = try? String(contentsOf: manifest, encoding: .utf8) else { return nil }

        let directory = appDirectory.lastPathComponent
        // 라이브러리·시뮬 코어는 Cloud Apps 소비 앱이 아니다.
        if directory.hasSuffix("-core") { return nil }
        if !declaresExecutable(package) { return nil }

        let sources = swiftSources(under: appDirectory.appendingPathComponent("Sources"))
        let cli = cliName(appDirectory: appDirectory)
        let hasGUIApp = sources.contains { src in
            conformsToScaffold(src.text) || declaresSwiftUIApp(src.text)
        }
        let cliChecks = sources.contains { src in
            guard mentions("GujoManaged.exitIfNotEntitled", in: src.text) else { return false }
            if isCLISource(src.url, cliName: cli) { return true }
            // Hummingbird 서버처럼 폴더명이 *CLI 가 아닌 유일한 executable.
            return !hasGUIApp
        }
        // 직접 부르거나, **스캐폴드 프로토콜을 쓰거나**. 후자는 `RanodeAppShell` 이
        // 대신 걸어준다 — 앱마다 한 줄을 붙이지 않는 것이 이 시스템의 요점이라,
        // 스캐폴드 채택을 미채택으로 세면 통일화를 거꾸로 재촉하게 된다.
        // AppKit 진입은 View modifier 대신 `GujoManaged.status` + `handOff` 로 막는다.
        // status/handOff 가 **CLI 소스**에만 있으면 GUI 게이트로 세지 않는다
        // (fixture·문서 예시가 CLI 에 status 를 넣어도 macOS 를 오탐하지 않게).
        // `exitIfNotEntitled*` 는 CLI 전용 패턴이다.
        let guiCalls = sources.contains { src in
            if mentions(".gujoManaged()", in: src.text) || conformsToScaffold(src.text) {
                return true
            }
            if isCLISource(src.url, cliName: cli) { return false }
            return mentions("GujoManaged.status", in: src.text)
                || mentions("GujoManaged.handOff", in: src.text)
        }
        // iOS 함대 앱은 GUI 에 `.gujoManaged()` 를 **걸면 안 된다**(gujo-managed.md
        // 2026-08-05 사고). 정본은 CLI 게이트(`exitIfNotEntitled*`). CLI 가 원장에
        // 물으면 managed 로 센다 — trait-only 로 밀어 에이전트가 금지된 GUI 게이트를
        // 붙이게 만들지 않는다.
        let iosCLIManaged = isIOSFleetApp(directory: directory) && cliChecks
        // GUI 창이 없는 패키지(서버·파이프라인 CLI)는 CLI 원장 조회가 게이트다.
        let cliOnlyManaged = cliChecks && !hasGUIApp

        return AppRecord(
            directory: directory,
            traitEnabled: declaresTrait(package),
            callsGate: guiCalls || iosCLIManaged || cliOnlyManaged,
            cliName: cli,
            cliConsultsLedger: cliChecks,
            dependsOnLicenseKit: declaresLicenseKitDependency(package),
            usesLegacyLicenseAPI: sources.contains { sourceUsesLegacyLicenseAPI(in: $0.text) })
    }

    public static func summarize(_ records: [AppRecord]) -> Summary {
        var s = Summary()
        for r in records {
            s.total += 1
            switch r.state {
            case .managed: s.managed += 1
            case .traitOnly: s.traitOnly += 1
            case .notAdopted: s.notAdopted += 1
            }
            if r.hasUngatedCLI { s.ungatedCLI += 1 }
            if r.hasLegacyLicensePath { s.legacyLicensePath += 1 }
        }
        return s
    }

    // MARK: - 읽기 세부

    /// `traits:` 배열 안에 `"GujoManaged"` 가 있나.
    ///
    /// 문자열이 주석이나 설명문에 나오는 것과 구분해야 해서 `traits:` 를 먼저 찾는다 —
    /// 단순 `contains("GujoManaged")` 는 이 파일을 설명하는 주석에도 걸린다.
    static func declaresTrait(_ package: String) -> Bool {
        var cursor = package.startIndex
        while let traits = package.range(of: "traits:", range: cursor..<package.endIndex) {
            guard let open = package.range(of: "[", range: traits.upperBound..<package.endIndex),
                  let close = package.range(of: "]", range: open.upperBound..<package.endIndex)
            else { return false }
            if package[open.upperBound..<close.lowerBound].contains("\"GujoManaged\"") {
                return true
            }
            cursor = close.upperBound
        }
        return false
    }

    /// Package.swift 가 LicenseKit product 를 **직접** 의존하는가.
    /// `code()` 는 문자열 내용을 지워서 product name 을 못 본다 — 줄 주석만 배제한다.
    static func declaresLicenseKitDependency(_ package: String) -> Bool {
        package.split(whereSeparator: \.isNewline).contains { raw in
            let s = String(raw)
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { return false }
            if s.contains(".product(name: \"LicenseKit\"") { return true }
            return s.contains("name: \"LicenseKit\"") && s.contains("product")
        }
    }

    /// 앱 소스가 옛 키 활성화 경로를 **코드로** 쓰는가.
    static func sourceUsesLegacyLicenseAPI(in text: String) -> Bool {
        if mentions("import LicenseKit", in: text) { return true }
        for needle in ["activate(licenseKey", "LicenseManager(", "licenseKey:", "LicenseLinkView"] {
            if mentions(needle, in: text) { return true }
        }
        return false
    }

    /// 실행 제품이 있는 소비 앱인가. 라이브러리만 있는 패키지는 게이트 대상이 아니다.
    static func declaresExecutable(_ package: String) -> Bool {
        package.contains(".executable(") || package.contains(".executableTarget(")
    }

    /// SwiftUI `@main struct …: App` 창 진입. `AppModel` 오탐을 피한다.
    static func declaresSwiftUIApp(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
            let code = code(in: String(line))
            guard code.contains("struct "), let r = code.range(of: ": App") else { return false }
            let after = code[r.upperBound...].first
            return after == nil || after == " " || after == "{" || after == ","
        }
    }

    /// 함대 디렉터리 관례로 iOS/iPad 앱인가.
    /// `platforms:` 만 보면 macOS 스텁 컴파일용 `.macOS` 도 같이 선언돼 있어 구분 불가.
    static func isIOSFleetApp(directory: String) -> Bool {
        let d = directory.lowercased()
        if d.hasSuffix("-ios") || d.hasSuffix("ios") { return true }
        if d.contains("-ios-") || d.contains("ios-") { return true }
        if d.hasSuffix("-ipad") || d.contains("-ipad-") { return true }
        return false
    }

    /// dual-entry CLI 이름 — `interop.json` 이 정본이다(계약 파일).
    public static func cliName(appDirectory: URL) -> String? {
        let url = appDirectory.appendingPathComponent("interop.json")
        guard let data = try? Data(contentsOf: url),
              let object = ({ () -> Any? in do { return try JSONSerialization.jsonObject(with: data) } catch { return nil } }()) as? [String: Any],
              let cli = object["cli"] as? String, !cli.isEmpty
        else { return nil }
        return cli
    }

    /// `FleetManagedApp` / `FleetManagedMenuBarApp` 채택 — 스캐폴드가 게이트를 대신 건다.
    static func conformsToScaffold(_ text: String) -> Bool {
        ["FleetManagedApp", "FleetManagedMenuBarApp", "FleetManagedWindowGroupApp",
         "FleetManagedMenuBarWindowGroupApp", "FleetManagedMenuBarExtraApp",
         "RanodeApp", "RanodeMenuBarApp", "RanodeWindowGroupApp",
         "RanodeMenuBarWindowGroupApp"].contains { name in
            text.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
                let code = code(in: String(line))
                guard code.contains("struct "), code.contains(": ") else { return false }
                // `: RanodeApp` · `: RanodeApp {` · `: RanodeMenuBarApp,` 만.
                // `RanodeAppBootstrap` 같은 접두 일치를 배제한다.
                guard let r = code.range(of: name) else { return false }
                let after = code[r.upperBound...].first
                return after == nil || after == " " || after == "{" || after == ","
            }
        }
    }

    /// 소스에 **코드로서** 나오는가 — 주석과 문자열 리터럴 안은 안 센다.
    ///
    /// 실측(2026-08-05): 이 스캐너를 쓰는 콘솔 앱이 안내 문구에 `.gujoManaged()` 를
    /// 적었다는 이유로 **자기 자신을 managed 로 셌다**. grep 으로 교차검증했지만
    /// grep 도 같은 맹점이라 둘이 사이좋게 틀린 값에 합의했다 — 맹점을 공유하는
    /// 두 방법이 일치하는 건 검증이 아니다.
    static func mentions(_ needle: String, in text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .contains { code(in: String($0)).contains(needle) }
    }

    /// 한 줄에서 주석과 문자열 리터럴 내용을 지운 나머지.
    ///
    /// 완전한 Swift 파서가 아니다 — 여러 줄 문자열·중첩 보간까지 다루지 않는다.
    /// 목적은 "설명문에 적힌 이름" 과 "실제 호출" 을 가르는 것뿐이고, 그 경계에서
    /// 틀리면 **덜 세는 쪽**(false negative)으로 틀린다. 채택률을 부풀리는 것보다 낫다.
    public static func code(in line: String) -> String {
        var out = ""
        var inString = false
        var escaped = false
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == "/", line.index(after: index) < line.endIndex,
                      line[line.index(after: index)] == "/" {
                break
            } else {
                out.append(ch)
            }
            index = line.index(after: index)
        }
        return out
    }

    /// LicenseKit 이 **본업**인 앱 — 키 원장·지갑·스토어·배포·키 활성화 제품.
    /// 이 앱들의 `import LicenseKit` 은 "옛 잔존" 이 아니라 제품 표면이다.
    public static func isLicenseKitKeeper(directory: String) -> Bool {
        let d = directory.lowercased()
        if d.hasPrefix("license-") { return true }
        switch d {
        case "swift-app-store-swift",
             "app-build-manager-swift",
             "backup-duplicate-manager-swift",
             "gujo-account-manager-swift",
             "gujo-skill-store-swift":
            return true
        default:
            return false
        }
    }

    /// CLI dual-entry 소스인가.
    /// - `*CLI` / `*CTL` / `*CommandLine` 타깃 디렉터리 (대소문자 무시)
    /// - interop `cli` 이름·basename 과 같거나 `{cli}-cli` / compact 형태
    /// - package-identity `gui_product` 가 `*App` 이면 stem 폴더는 CLI 제품
    /// - Entry.swift / *CLI.swift / AXORCMain.swift
    public static func isCLISource(_ url: URL, cliName: String? = nil) -> Bool {
        let comps = url.pathComponents
        if comps.contains(where: { name in
            let lower = name.lowercased()
            return lower.hasSuffix("cli")
                || lower.hasSuffix("ctl")
                || lower.hasSuffix("commandline")
        }) {
            return true
        }
        let base = url.deletingPathExtension().lastPathComponent
        let baseLower = base.lowercased()
        if base == "Entry" || base == "AXORCMain" || baseLower.hasSuffix("cli") {
            return true
        }
        let parent = url.deletingLastPathComponent().lastPathComponent
        let parentLower = parent.lowercased()

        // package-identity dual-entry: GUI=`AgentE2ERunnerApp`, CLI 폴더=`AgentE2ERunner`
        if let gui = packageIdentityGUIProduct(near: url), gui.hasSuffix("App") {
            let stem = String(gui.dropLast(3))
            if parent == stem || parentLower == stem.lowercased() {
                return true
            }
        }

        if let cli = cliName {
            let bare = URL(fileURLWithPath: cli).lastPathComponent
            let bareLower = bare.lowercased()
            let compact = bareLower.replacingOccurrences(of: "-", with: "")
            if parent == bare || parent == cli
                || parentLower == bareLower
                || parentLower == bareLower + "-cli"
                || parentLower == bareLower + "cli"
                || parentLower == compact + "cli"
            {
                return true
            }
            let parentCompact = parentLower.replacingOccurrences(of: "-", with: "")
            let looksCLIFolder = parentLower.contains("cli")
                || parentLower.hasSuffix("ctl")
                || parent.contains("-")
                || parent == parent.lowercased()
            if looksCLIFolder, parentCompact.count >= 8, compact.count >= 8 {
                let shared = zip(parentCompact, compact).prefix(while: { $0 == $1 }).count
                if shared >= 8, abs(parentCompact.count - compact.count) <= 4 {
                    return true
                }
            }
        }
        return false
    }

    /// `…/apps/<dir>/Sources/…` 에서 Packaging/package-identity.json 의 gui_product.
    static func packageIdentityGUIProduct(near url: URL) -> String? {
        var dir = url.deletingLastPathComponent()
        for _ in 0..<8 {
            let identity = dir
                .appendingPathComponent("Packaging", isDirectory: true)
                .appendingPathComponent("package-identity.json")
            if let data = try? Data(contentsOf: identity),
               let obj = ({ () -> Any? in do { return try JSONSerialization.jsonObject(with: data) } catch { return nil } }()) as? [String: Any],
               let gui = obj["gui_product"] as? String, !gui.isEmpty {
                return gui
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    struct Source {
        let url: URL
        let text: String
    }

    static func swiftSources(under root: URL) -> [Source] {
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var out: [Source] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out.append(Source(url: url, text: text))
        }
        return out
    }
}
