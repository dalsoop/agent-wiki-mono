import XCTest
@testable import LocalizationKit

final class CLILocalizationTests: XCTestCase {
    private var tmp: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("CLIL10n-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        suiteName = "CLIL10n-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        do { try FileManager.default.removeItem(at: tmp) }
        catch { fputs("fixture cleanup 실패: \(error)\n", stderr) }
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// en/ko 테이블이 든 더미 번들(.app/Contents/Resources/<Pkg>_<Target>.bundle 레이아웃).
    private func makeCatalogBundle() throws -> Bundle {
        let b = tmp.appendingPathComponent("DemoApp_DemoApp.bundle", isDirectory: true)
        for (code, value) in [("en", "open failed: %@"), ("ko", "열기 실패: %@")] {
            let lproj = b.appendingPathComponent("\(code).lproj", isDirectory: true)
            try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
            try """
            "cli.error.open" = "\(value)";
            "cli.usage" = "\(code == "ko" ? "사용법" : "Usage")";
            """.write(
                to: lproj.appendingPathComponent("Localizable.strings"),
                atomically: true, encoding: .utf8
            )
        }
        return try XCTUnwrap(Bundle(url: b))
    }

    func testStoredLanguageSelectsTable() throws {
        let base = try makeCatalogBundle()
        defaults.set("ko", forKey: "app.language")
        XCTAssertEqual(
            CLILocalization.string("cli.usage", defaultsKey: "app.language", userDefaults: defaults, base: base),
            "사용법"
        )
        defaults.set("en", forKey: "app.language")
        XCTAssertEqual(
            CLILocalization.string("cli.usage", defaultsKey: "app.language", userDefaults: defaults, base: base),
            "Usage"
        )
    }

    func testMissingKeyEchoesKey() throws {
        let base = try makeCatalogBundle()
        defaults.set("ko", forKey: "app.language")
        XCTAssertEqual(
            CLILocalization.string("cli.no.such.key", defaultsKey: "app.language", userDefaults: defaults, base: base),
            "cli.no.such.key"
        )
    }

    func testFormatSpecRoundTrips() throws {
        let base = try makeCatalogBundle()
        defaults.set("ko", forKey: "app.language")
        let template = CLILocalization.string(
            "cli.error.open", defaultsKey: "app.language", userDefaults: defaults, base: base
        )
        XCTAssertEqual(template, "열기 실패: %@")
        // 포맷 치환 자체는 stdlib String(format:) — 값의 %@ 자리가 실제로 채워지는지만.
        XCTAssertEqual(String(format: template, arguments: ["사유"]), "열기 실패: 사유")
    }

    /// 설치본 Helpers CLI(.app/Contents/Helpers/<cli>)에서 앱 Resources 번들에 닿는지 —
    /// resourceRoots 의 두 칸 위 hop.
    func testHelpersCLIReachesAppResources() throws {
        let app = tmp.appendingPathComponent("Demo.app", isDirectory: true)
        let helpers = app.appendingPathComponent("Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: helpers.appendingPathComponent("demo-cli"),
            withDestinationURL: URL(fileURLWithPath: "/usr/bin/true")
        )
        let b = app.appendingPathComponent("Contents/Resources/DemoApp_DemoApp.bundle", isDirectory: true)
        let lproj = b.appendingPathComponent("ko.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        try "\"cli.usage\" = \"사용법\";".write(
            to: lproj.appendingPathComponent("Localizable.strings"),
            atomically: true, encoding: .utf8
        )

        // Helpers 디렉터리를 main 번들로 삼은 실행 모형
        let main = try XCTUnwrap(Bundle(url: helpers))
        let roots = ResourceBundle.resourceRoots(main: main)
        XCTAssertTrue(
            roots.contains { $0.standardizedFileURL.path == app.appendingPathComponent("Contents/Resources").standardizedFileURL.path },
            "Helpers CLI 루트에 앱 Resources 가 없다: \(roots)"
        )
        let resolved = ResourceBundle.resolveLocalization(preferredName: nil, roots: roots, appName: "demo-cli")
        XCTAssertNotNil(resolved, "앱 Resources 의 로캐이즈 번들을 못 찾았다")
        defaults.set("ko", forKey: "app.language")
        XCTAssertEqual(
            resolved.map { CLILocalization.string("cli.usage", defaultsKey: "app.language", userDefaults: defaults, base: $0) },
            "사용법"
        )
    }

    /// Helpers CLI **실행 파일** URL(.app/Contents/Helpers/<cli>)에서 두 칸 위 hop —
    /// 실제 Bundle.main 은 실행 파일 자체라 디렉터리 모형으로는 안 잡히던 경우
    /// (2026-08-22 설치본 실측: 디렉터리 모형 테스트는 통과하는데 설치본은 전 키 raw).
    func testHelpersCLIFileURLReachesAppResources() throws {
        let app = tmp.appendingPathComponent("Demo.app", isDirectory: true)
        let cli = app.appendingPathComponent("Contents/Helpers/demo-cli")
        XCTAssertTrue(
            ResourceBundle.helpersAppResourceRoots(cliURL: cli).contains {
                $0.standardizedFileURL.path
                    == app.appendingPathComponent("Contents/Resources").standardizedFileURL.path
            },
            "실행 파일 URL에서 앱 Resources 후보가 나와야 한다"
        )
    }

    /// PATH 심링크(/opt/homebrew/bin/<cli>)로 실행된 경우 — Bundle.main 이 심링크
    /// 경로에 붙어 원본 URL 로는 앱 Resources 에 닿지 못한다(2026-08-22 실측:
    /// 실 경로 실행은 한국어, 심링크 실행만 전 키 raw).
    func testSymlinkedHelpersCLIReachesAppResources() throws {
        let app = tmp.appendingPathComponent("Demo.app", isDirectory: true)
        let realCLI = app.appendingPathComponent("Contents/Helpers/demo-cli")
        try FileManager.default.createDirectory(
            at: realCLI.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: realCLI.path, contents: Data())
        let link = tmp.appendingPathComponent("demo-cli-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: realCLI)

        XCTAssertFalse(
            ResourceBundle.helpersAppResourceRoots(cliURL: link).contains {
                $0.standardizedFileURL.path
                    == app.appendingPathComponent("Contents/Resources").standardizedFileURL.path
            },
            "심링크 URL 원본만으로는 앱 Resources 에 닿으면 안 된다(실측 재현)"
        )
        XCTAssertTrue(
            ResourceBundle.helpersAppResourceRootsResolving(cliURL: link).contains {
                $0.standardizedFileURL.path
                    == app.appendingPathComponent("Contents/Resources").standardizedFileURL.path
            },
            "심링크 해석본 후보에는 앱 Resources 가 있어야 한다"
        )
    }

    /// 남의 SPM 번들이 깔린 bin 디렉터리(/opt/homebrew/bin 실측 — 번들 7개)를 지나
    /// 실행될 때 — 자기 .app Resources 후보가 **더 앞**에 있어야 남의 번들이 먼저
    /// 채택되지 않는다. resourceRoots 가 executableURL 강신호를 최우선에 둔 이유.
    func testAppResourcesBeatsPollutedBinRoot() throws {
        let app = tmp.appendingPathComponent("Demo.app", isDirectory: true)
        let realCLI = app.appendingPathComponent("Contents/Helpers/demo-cli")
        try FileManager.default.createDirectory(
            at: realCLI.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: realCLI.path, contents: Data())
        // 자기 번들: cli.usage 있음
        let good = app.appendingPathComponent("Contents/Resources/DemoApp_DemoApp.bundle", isDirectory: true)
        try FileManager.default.createDirectory(
            at: good.appendingPathComponent("ko.lproj", isDirectory: true),
            withIntermediateDirectories: true)
        try "\"cli.usage\" = \"사용법\";".write(
            to: good.appendingPathComponent("ko.lproj/Localizable.strings"),
            atomically: true, encoding: .utf8)
        // 오염된 bin: 남의 lproj 번들(cli 키 없음)
        let bin = tmp.appendingPathComponent("polluted-bin", isDirectory: true)
        let alien = bin.appendingPathComponent("Alien_Alien.bundle", isDirectory: true)
        try FileManager.default.createDirectory(
            at: alien.appendingPathComponent("ko.lproj", isDirectory: true),
            withIntermediateDirectories: true)
        try "\"alien.key\" = \"남의 값\";".write(
            to: alien.appendingPathComponent("ko.lproj/Localizable.strings"),
            atomically: true, encoding: .utf8)
        defaults.set("ko", forKey: "app.language")

        // resourceRoots 순서: 실행 파일 해석본 강신호 → resourceURL(=bin)
        let strongRoots = ResourceBundle.helpersAppResourceRootsResolving(cliURL: realCLI)
        let ordered = strongRoots + [bin]
        let bundle = try XCTUnwrap(
            ResourceBundle.resolveLocalization(preferredName: nil, roots: ordered, appName: "demo-cli"),
            "강신호 루트에서 자기 번들을 찾아야 한다"
        )
        XCTAssertEqual(
            CLILocalization.string("cli.usage", defaultsKey: "app.language", userDefaults: defaults, base: bundle),
            "사용법"
        )
        // 순서를 뒤집으면(옛 동작) 남의 번들이 먼저 채택된다 — 이 결함의 재현.
        let reversed = [bin] + strongRoots
        let alienBundle = try XCTUnwrap(
            ResourceBundle.resolveLocalization(preferredName: nil, roots: reversed, appName: "demo-cli")
        )
        XCTAssertEqual(
            CLILocalization.string("cli.usage", defaultsKey: "app.language", userDefaults: defaults, base: alienBundle),
            "cli.usage",
            "bin 이 앞서면 남의 번들이 걸려 raw 키로 샌다(옛 결함 재현)"
        )
    }
}

// MARK: - text(_:values:) 안전 진입점 (2026-09-01, %@ 슬롯에 Int → segfault 결함 류 대응)

extension CLILocalizationTests {
    /// Int 를 values 로 넘겨도 크래시 없이 "90" 으로 채워진다 — CVarArg 가 없기 때문.
    func testTextFillsObjectSlotWithNumberSafely() throws {
        let base = try makeCatalogBundle()
        defaults.set("ko", forKey: "app.language")
        XCTAssertEqual(
            CLILocalization.text("cli.error.open", defaultsKey: "app.language",
                                 userDefaults: defaults, base: base, values: 90),
            "열기 실패: 90"
        )
    }

    /// 위치 접두 슬롯 여러 개 — 순서대로 채운다.
    func testTextFillsPositionalSlotsInOrder() {
        XCTAssertEqual(
            CLILocalization.substituteSlots(into: "%2$@ 에게 %1$d개", values: [3, "철수"]),
            "철수 에게 3개"
        )
    }

    /// 정밀 지정자(`%.1f`)는 미지원 — 원문 보존. 유효한 암시 슬롯은 정상 채움.
    func testTextPreservesUnknownDirectives() {
        XCTAssertEqual(
            CLILocalization.substituteSlots(into: "%.1f MB / %d", values: [5]),
            "%.1f MB / 5"
        )
        XCTAssertEqual(
            CLILocalization.substituteSlots(into: "%q 와 %z", values: [1]),
            "%q 와 %z"
        )
    }

    /// `%%` 는 리터럴 퍼센트.
    func testTextKeepsLiteralPercent() {
        XCTAssertEqual(
            CLILocalization.substituteSlots(into: "%1$d%% done", values: [42]),
            "42% done"
        )
    }

    /// 슬롯 수보다 값이 적으면 그 슬롯은 원문 보존 — 조용한 빈칸보다 눈에 띄는 게 낫다.
    func testTextKeepsSlotWhenValueMissing() {
        XCTAssertEqual(
            CLILocalization.substituteSlots(into: "%1$@ / %2$@", values: ["a"]),
            "a / %2$@"
        )
    }

    /// `format(_:CVarArg...)` 에 Int, Double, Bool 등 원시 타입을 %@ 에 넘겨도
    /// CVarArg 포인터 역참조 크래시(SIGSEGV) 없이 안전하게 치환된다.
    func testFormatMethodWithNumericArgumentsDoesNotCrashAndSubstitutesSafely() throws {
        let base = try makeCatalogBundle()
        defaults.set("ko", forKey: "app.language")
        // "cli.error.open" = "열기 실패: %@" — %@ 슬롯에 Int(500) 를 직접 전달
        // 기존 String(format:) 이었으면 0x1f4 주소 역참조로 SIGSEGV 발생하던 케이스
        let result = CLILocalization.format(
            "cli.error.open", 500
        )
        // 번들이 기본 main 이 아닐 수 있으므로 substituteSlots 직접 검증도 함께 수행
        let direct = CLILocalization.substituteSlots(into: "오류 코드: %@ (포트 %d)", values: [500, 8080])
        XCTAssertEqual(direct, "오류 코드: 500 (포트 8080)")
    }

    // MARK: - 번들이 번들로 안 읽힐 때 (Linux 평면 리소스 번들, 2026-09-04 CI 실측)

    /// 번들 조회가 키를 그대로 돌려줘도 파일 카탈로그가 있으면 사람 말이 나와야 한다.
    func testFallsBackToFileCatalogWhenBundleLookupIsBlind() throws {
        let bundleURL = try makeCatalogBundle().bundleURL
        // `base` 는 키를 모르는 번들(테스트 러너의 main) — Linux 에서 CFBundle 이
        // 평면 번들을 인식하지 못해 벌어지는 상황과 같은 결과다.
        let value = CLILocalization.string(
            "cli.usage",
            userDefaults: defaults,
            base: .main,
            catalog: LocalizationCatalog(root: bundleURL)
        )
        // 어느 언어가 뽑히는지는 실행 머신의 시스템 언어에 달렸다 — 고정할 것은
        // "키가 아니라 문구가 나온다"는 사실이다.
        XCTAssertTrue(["Usage", "사용법"].contains(value),
                      "카탈로그가 있으면 키가 아니라 문구가 나와야 한다: \(value)")
    }

    /// 저장 언어가 있으면 카탈로그도 그 언어를 쓴다.
    func testFileCatalogHonoursStoredLanguage() throws {
        let bundleURL = try makeCatalogBundle().bundleURL
        defaults.set("ko", forKey: "app.language")
        let value = CLILocalization.string(
            "cli.usage",
            userDefaults: defaults,
            base: .main,
            catalog: LocalizationCatalog(root: bundleURL)
        )
        XCTAssertEqual(value, "사용법")
    }

    /// 카탈로그에도 없는 키는 키 그대로 — 누락은 드러나야 한다.
    func testUnknownKeyStaysRawWithCatalog() throws {
        let bundleURL = try makeCatalogBundle().bundleURL
        let value = CLILocalization.string(
            "cli.absent",
            userDefaults: defaults,
            base: .main,
            catalog: LocalizationCatalog(root: bundleURL)
        )
        XCTAssertEqual(value, "cli.absent")
    }
}
