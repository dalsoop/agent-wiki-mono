import Foundation

/// UserDefaults 백엔드 설정값 프로퍼티 래퍼. 앱의 `didSet { UserDefaults... }` 보일러플레이트를
/// 한 줄로 줄인다. Codable 값을 저장하며, 테스트는 `suiteName` 으로 격리한다.
///
/// ```swift
/// @Stored(key: "refreshInterval", default: 5.0) var refreshInterval: Double
/// @Stored(key: "theme", default: Theme.system) var theme: Theme   // Theme: Codable
/// ```
@propertyWrapper
public struct Stored<Value: Codable> {
    private let key: String
    private let defaultValue: Value
    private let defaults: UserDefaults

    public init(key: String, default defaultValue: Value, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.defaults = defaults
    }

    public var wrappedValue: Value {
        get {
            guard let data = defaults.data(forKey: key),
                  let value = try? JSONDecoder().decode(Value.self, from: data) else {
                return defaultValue
            }
            return value
        }
        nonmutating set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            }
        }
    }
}
