import Foundation

/// 설치본마다 고르는 Sparkle 업데이트 채널.
///
/// appcast 는 채널 쿼리 없는 피드 하나에 모든 채널 항목을 싣고, stable 이 아닌 항목에만
/// `<sparkle:channel>beta|alpha|dev</sparkle:channel>` 을 붙인다. Sparkle 2 는 태그 없는
/// 항목과 `allowedChannels(for:)` 가 돌려준 채널의 항목만 본다.
///
/// 설정은 앱 자신의 기본 defaults 도메인(`UserDefaults.standard`)의 `GujoUpdateChannel`
/// 키에 둔다. 그래서 다른 앱이 `defaults write <번들ID> GujoUpdateChannel dev` 로 바꿀 수 있다.
/// 키가 없거나 모르는 값이면 stable 이다.
public enum UpdateChannel: String, CaseIterable, Sendable {
    case stable
    case beta
    case alpha
    case dev

    /// 앱 기본 defaults 도메인의 키 이름.
    public static let defaultsKey = "GujoUpdateChannel"

    /// 문자열을 채널로 읽는다. nil 이거나 모르는 값이면 stable.
    public static func parse(_ raw: String?) -> UpdateChannel {
        guard let raw else { return .stable }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return UpdateChannel(rawValue: normalized) ?? .stable
    }

    /// 앱 기본 defaults 도메인에 저장된 현재 채널.
    public static var current: UpdateChannel { current(in: .standard) }

    /// 주어진 defaults 에 저장된 채널. 테스트는 별도 suite 를 넘긴다.
    public static func current(in defaults: UserDefaults) -> UpdateChannel {
        parse(defaults.string(forKey: defaultsKey))
    }

    /// 앱 기본 defaults 도메인에 채널을 저장한다.
    public static func set(_ channel: UpdateChannel) { set(channel, in: .standard) }

    /// 주어진 defaults 에 채널을 저장한다.
    public static func set(_ channel: UpdateChannel, in defaults: UserDefaults) {
        defaults.set(channel.rawValue, forKey: defaultsKey)
    }

    /// 이 채널을 고른 설치본이 Sparkle 에 허용할 채널 이름 집합.
    ///
    /// 덜 불안정한 채널을 포함한다. stable 은 빈 집합이다(태그 없는 항목은 Sparkle 이 항상 본다).
    public var allowedSparkleChannels: Set<String> {
        Self.allowedSparkleChannels(for: self)
    }

    /// 허용 채널 규칙. stable → {}, beta → {beta}, alpha → {beta, alpha},
    /// dev → {beta, alpha, dev}.
    public static func allowedSparkleChannels(for channel: UpdateChannel) -> Set<String> {
        switch channel {
        case .stable: []
        case .beta: [UpdateChannel.beta.rawValue]
        case .alpha: [UpdateChannel.beta.rawValue, UpdateChannel.alpha.rawValue]
        case .dev: [UpdateChannel.beta.rawValue, UpdateChannel.alpha.rawValue, UpdateChannel.dev.rawValue]
        }
    }
}

#if canImport(AppKit)
import Sparkle

/// `allowedChannels(for:)` 로 설치본의 채널 설정을 Sparkle 에 넘기는 델리게이트.
///
/// Sparkle 은 delegate 를 약하게 잡으므로 `SparkleUpdaterHost` 가 강하게 붙잡는다.
/// 설정은 매 확인 때 다시 읽는다. 채널을 바꾸면 앱을 다시 켜지 않아도 다음 확인부터 적용된다.
final class UpdateChannelDelegate: NSObject, SPUUpdaterDelegate {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        UpdateChannel.current(in: defaults).allowedSparkleChannels
    }
}
#endif
