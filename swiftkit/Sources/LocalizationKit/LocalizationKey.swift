import Foundation

/// 앱 `L10nKey` 가 채택한다. `String` 과는 겹치지 않는다(`RawRepresentable` 단독은 모호함).
public protocol LocalizationKey: Sendable {
    var rawValue: String { get }
}
