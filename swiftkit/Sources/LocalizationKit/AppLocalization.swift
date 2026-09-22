// Combine 은 Darwin 전용이다(corelibs 에 없다). agent-lint-catalog CLI 처럼
// Linux 도커(native-lint 잡)에서 빌드되는 타깃도 LocalizationKit 을 링크하므로
// 이 GUI 접착 파일만 조건부로 컴파일한다(2026-08-22, CLI i18n 채택).
#if canImport(Combine)
import Combine
import Foundation

/// `@Observable` `LocalizationManager` 를 Combine `ObservableObject` 로 잇는다.
/// `AppModel` 이 소유하고 `objectWillChange` 를 재발행하면 언어 전환이 즉시 그려진다.
@MainActor
public final class AppLocalization: ObservableObject {
    public let manager: LocalizationManager

    public var language: AppLanguage { manager.language }

    public init(
        baseBundle: Bundle,
        defaultsKey: String = "app.language",
        userDefaults: UserDefaults = .standard
    ) {
        self.manager = LocalizationManager(
            baseBundle: baseBundle,
            defaultsKey: defaultsKey,
            userDefaults: userDefaults
        )
    }

    public func setLanguage(_ language: AppLanguage) {
        objectWillChange.send()
        manager.setLanguage(language)
    }

    public func string(_ key: String) -> String {
        manager.string(key)
    }

    public func string(_ key: String, _ args: CVarArg...) -> String {
        let values: [any CustomStringConvertible] = args.map { String(describing: $0) }
        return CLILocalization.substituteSlots(into: manager.string(key), values: values)
    }

    public func string(_ key: some LocalizationKey) -> String {
        string(key.rawValue)
    }

    public func string(_ key: some LocalizationKey, _ args: CVarArg...) -> String {
        let values: [any CustomStringConvertible] = args.map { String(describing: $0) }
        return CLILocalization.substituteSlots(into: string(key.rawValue), values: values)
    }
}
#endif
