import Foundation

/// CLI 실행 파일용 일회성 문자열 조회 — `@MainActor` 관찰자 없이 즉시 값을 돌린다.
///
/// 배경(2026-08, app-i18n-inspector CLI 축 실측): 함대 CLI 출력 문자열 i18n 채택이 0%다.
/// `LocalizationManager` 는 GUI 런타임 전환용이라 `@MainActor` 관찰자를 전제하고 있어
/// 동기 top-level CLI 코드에서 그대로 쓸 수 없다. CLI 는 전환이 없다 — 저장된 언어를
/// 한 번 읽고 조회마다 값을 돌리는 이 진입점이 맞다. 키·번들 계약은 manager 와 같다:
/// 누락 시 키를 그대로 반환(→ 테스트가 감지).
///
/// 번들은 `ResourceBundle.localization()` 으로 찾는다 — 설치본 Helpers CLI 에선
/// .app/Contents/Resources 의 앱 번들, `swift run` 개발 중엔 실행 파일 옆 번들.
/// 키 정본은 앱의 Localizable.strings(GUI 타깃 리소스)이므로 CLI 는 테이블을 별도로
/// 두지 않는다.
public enum CLILocalization {
    /// 현재 언어의 문자열. 언어는 UserDefaults 저장값(기본 `.system`).
    ///
    /// 번들 API 가 키를 그대로 돌려주면 **파일로 한 번 더 본다**(`catalog`). Linux
    /// (swift-corelibs-foundation)에선 SwiftPM 평면 리소스 번들이 CFBundle 에 번들로
    /// 인식되지 않아 이 위의 세 줄이 통째로 빈손이다 — 2026-09-04 실측으로 native-lint
    /// 게이트 출력 전체가 키(`cli.contracts.ok_row`)로 샜다. `@autoclosure` 라 조회가
    /// 성공하는 경로(macOS)에선 카탈로그를 찾지도 않는다.
    public static func string(
        _ key: String,
        defaultsKey: String = "app.language",
        userDefaults: UserDefaults = .standard,
        base: Bundle = ResourceBundle.localization(),
        catalog: @autoclosure () -> LocalizationCatalog? = ResourceBundle.localizationCatalog()
    ) -> String {
        let stored = userDefaults.string(forKey: defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        let code: String
        switch stored {
        case .system: code = LocalizationManager.systemLocalization(in: base)
        case .korean, .english: code = stored.rawValue
        }
        let lproj = base.path(forResource: code, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? base
        let value = lproj.localizedString(forKey: key, value: key, table: nil)
        if value != key { return value }
        guard let catalog = catalog() else { return key }
        // `.system` 은 번들이 못 읽히면 언어 판정도 못 했다 — 카탈로그가 담은 번역에서 다시 고른다.
        let preferred = stored == .system
            ? [catalog.systemLocalization(), code].compactMap { $0 }
            : [code]
        return catalog.string(key, preferred: preferred) ?? key
    }

    /// 포맷 인자 버전 — `CLILocalization.format("cli.error.open", error.localizedDescription)`.
    /// en/ko 값의 포맷 지정자는 같아야 한다(app-i18n-inspector formatSpecMismatch 검사).
    /// (`string(_:)` 오버로드와의 모호성 때문에 이름을 달리 한다.)
    ///
    /// 2026-09-02: CVarArg 가 C `String(format:)` 으로 넘어갈 때 `%@` 에 Int 가 오면
    /// 발생하는 SIGSEGV(objc_respondsToSelector 주소 역참조)를 근본 차단하기 위해
    /// `substituteSlots` 를 거치도록 통일. CVarArg 인자도 `String(describing:)` 으로
    /// 안전하게 변환되어 슬롯에 채워진다.
    public static func format(_ key: String, _ args: CVarArg...) -> String {
        format(key, arguments: args)
    }

    public static func format(_ key: String, arguments: [CVarArg]) -> String {
        let values: [any CustomStringConvertible] = arguments.map { String(describing: $0) }
        return substituteSlots(into: string(key), values: values)
    }

    public static func format(_ key: some LocalizationKey, arguments: [CVarArg]) -> String {
        format(key.rawValue, arguments: arguments)
    }

    public static func format(_ key: some LocalizationKey, _ args: CVarArg...) -> String {
        format(key.rawValue, arguments: args)
    }

    /// 보간 기반 안전 진입점 — `CLILocalization.text("elapsed", values: 90)`.
    ///
    /// `String(format:)` 을 거치지 않는다. 테이블 문구의 `%n$@`·`%n$d` 슬롯을
    /// `values` 의 `String(describing:)` 으로 순서대로 채운다. CVarArg 가 없으니
    /// 타입 불일치 크래시가 원리적으로 불가능하고, `%@` 슬롯에 Int 를 넘겨도
    /// "90" 으로 채워질 뿐이다. 정밀 지정자(`%.1f`)는 지원하지 않는다 — 소수
    /// 정밀도가 필요하면 호출처에서 `String(format: "%.1f", v)` 로 문자열을 만들어 넘긴다.
    public static func text(
        _ key: String,
        defaultsKey: String = "app.language",
        userDefaults: UserDefaults = .standard,
        base: Bundle = ResourceBundle.localization(),
        values: any CustomStringConvertible...
    ) -> String {
        substituteSlots(into: string(key, defaultsKey: defaultsKey,
                                     userDefaults: userDefaults, base: base),
                        values: values)
    }

    /// 테이블 문구의 지정자를 값으로 채운다. 위치 접두(`%n$`)와 암시(`%@`) 둘 다
    /// 지원 — 암시 슬롯은 등장 순서대로 값을 소비한다. 모르는 패턴은 원문 보존 —
    /// C 포맷을 재해석하지 않으니 잘못될 일이 없다.
    public static func substituteSlots(into format: String,
                                       values: [any CustomStringConvertible]) -> String {
        // `%%` → 리터럴 `%` 먼저 보호.
        let placeholder = "\u{E000}"  // 사유영역 — 테이블에 등장하지 않는다.
        var work = format.replacingOccurrences(of: "%%", with: placeholder)
        let pattern = #"%(\d+\$)?(?:ll|l|hh|h|z|t|j|q|L)?[@dDiIuUxXoOfFeEgGaAcCsSp]"#
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            return format
        }
        let ns = work as NSString
        var replacements: [(NSRange, String)] = []
        var nextImplicit = 1
        for m in regex.matches(in: work, range: NSRange(location: 0, length: ns.length)) {
            let position: Int
            if m.range(at: 1).location != NSNotFound,
               let idxRange = Range(m.range(at: 1), in: work) {
                position = Int(work[idxRange].dropLast()) ?? 0
            } else {
                position = nextImplicit
            }
            guard (1...values.count).contains(position),
                  Range(m.range, in: work) != nil
            else { continue }
            if m.range(at: 1).location == NSNotFound { nextImplicit += 1 }
            replacements.append((m.range, values[position - 1].description))
        }
        // 뒤에서부터 치환해 오프셋 무효화를 피한다.
        for (range, value) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            work = (work as NSString).replacingCharacters(in: range, with: value)
        }
        return work.replacingOccurrences(of: placeholder, with: "%")
    }
}
