import Foundation

/// 설정 영속화 추상화. 앱마다 `didSet { UserDefaults.standard.set(...) }` 를 흩뿌리던 것을
/// 하나의 주입 가능한 저장소로 모은다. 테스트는 InMemorySettingsStore 를 주입한다.
public protocol SettingsStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
}

public extension SettingsStore {
    /// Codable 값을 읽는다. 없거나 디코딩 실패 시 nil.
    func read<T: Codable>(_ type: T.Type = T.self, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Codable 값을 저장한다. nil 이면 삭제.
    func write<T: Codable>(_ value: T?, forKey key: String) {
        guard let value else { set(nil, forKey: key); return }
        set(try? JSONEncoder().encode(value), forKey: key)
    }

    /// 기본값을 곁들인 편의 읽기.
    func value<T: Codable>(forKey key: String, default fallback: T) -> T {
        read(T.self, forKey: key) ?? fallback
    }
}

/// UserDefaults 백엔드.
public final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults
    public init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func data(forKey key: String) -> Data? { defaults.data(forKey: key) }
    public func set(_ data: Data?, forKey key: String) {
        if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

/// 테스트용 인메모리 저장소(디스크·UserDefaults 오염 없음).
public final class InMemorySettingsStore: SettingsStore {
    private var storage: [String: Data] = [:]
    public init() {}
    public func data(forKey key: String) -> Data? { storage[key] }
    public func set(_ data: Data?, forKey key: String) { storage[key] = data }
}
