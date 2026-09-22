import Foundation
import Observation

/// 런타임 KR/EN 전환 메커니즘. 문자열 리소스는 호출 앱이 자기 번들(`baseBundle`)로 제공한다.
/// 선택 언어의 `.lproj` 서브번들을 로드해 재시작 없이 즉시 전환한다.
@MainActor
@Observable
public final class LocalizationManager {
    private let baseBundle: Bundle
    private let defaultsKey: String
    private let userDefaults: UserDefaults

    public private(set) var language: AppLanguage
    private var activeBundle: Bundle

    public init(baseBundle: Bundle,
                defaultsKey: String = "app.language",
                userDefaults: UserDefaults = .standard) {
        self.baseBundle = baseBundle
        self.defaultsKey = defaultsKey
        self.userDefaults = userDefaults
        let stored = userDefaults.string(forKey: defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        self.language = stored
        self.activeBundle = Self.resolveBundle(for: stored, in: baseBundle)
    }

    /// 언어를 바꾸고 영속화한다. `@Observable` 이라 SwiftUI 뷰가 자동 리렌더된다.
    public func setLanguage(_ language: AppLanguage) {
        self.language = language
        userDefaults.set(language.rawValue, forKey: defaultsKey)
        self.activeBundle = Self.resolveBundle(for: language, in: baseBundle)
    }

    /// raw 키로 현재 언어 문자열을 가져온다. 누락 시 키를 그대로 반환(→ 테스트가 감지).
    public func string(_ key: String) -> String {
        activeBundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// 포맷 인자 안전 치환 — C `String(format:)`의 `%@`에 Int 전달 시 발생하는 SIGSEGV를 원천 차단한다.
    public func format(_ key: String, _ args: CVarArg...) -> String {
        format(key, arguments: args)
    }

    public func format(_ key: String, arguments: [CVarArg]) -> String {
        let values: [any CustomStringConvertible] = arguments.map { String(describing: $0) }
        return CLILocalization.substituteSlots(into: string(key), values: values)
    }

    /// 이 번들이 실제로 **담고 있는** 번역 목록(`Base` 제외).
    ///
    /// 지원 언어의 정본은 열거형이 아니라 번들에 든 `.lproj` 다 — 앱마다 다르고
    /// 새 번역을 넣는 순간 늘어난다.
    ///
    /// `nonisolated`: 인자만 쓰는 순수 함수라 CLI(`CLILocalization`) 같은 비동기
    /// 컨텍스트에서도 같은 정본 로직을 쓴다.
    public nonisolated static func availableLocalizations(in base: Bundle) -> [String] {
        base.localizations.filter { $0 != "Base" }.sorted()
    }

    /// 이 매니저가 쓸 수 있는 번역 목록.
    public var availableLocalizations: [String] {
        Self.availableLocalizations(in: baseBundle)
    }

    private static func resolveBundle(for language: AppLanguage, in base: Bundle) -> Bundle {
        switch language {
        case .system:
            return bundle(forLocalization: systemLocalization(in: base), in: base) ?? base
        case .korean, .english:
            return bundle(forLocalization: language.rawValue, in: base) ?? base
        }
    }

    private static func bundle(forLocalization code: String, in base: Bundle) -> Bundle? {
        guard let path = base.path(forResource: code, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }

    /// 시스템 우선 언어를 **앱이 실제로 담고 있는 번역** 중에서 고른다.
    ///
    /// 종전에는 "`ko` 로 시작하면 한국어, 아니면 영어"였다. 그래서 `.lproj` 를 새로 넣어도
    /// 매니저가 절대 로드하지 않았다 — 일본어 번역을 넣어도 일본어 사용자는 영어를 봤다.
    /// 이제 Foundation 매칭에 맡겨 지역 변종(`zh-Hans`/`zh-Hant`, `pt-BR`)까지 표준 규칙으로 고른다.
    ///
    /// 번들의 암묵적 `.system` 해석에 맡기지 않는 건 종전과 같은 이유다 — loose 실행이나
    /// 일부 번들 구성에서 개발 지역(en)으로 잘못 떨어져 한국 시스템에서도 영어가 떴다.
    ///
    /// `nonisolated`: `availableLocalizations` 와 같은 이유 — CLI(`CLILocalization`) 공유.
    nonisolated static func systemLocalization(in base: Bundle) -> String {
        let available = availableLocalizations(in: base)
        guard !available.isEmpty else { return "en" }
        let matched = Bundle.preferredLocalizations(
            from: available, forPreferences: Locale.preferredLanguages
        )
        return matched.first ?? available.first ?? "en"
    }
}
