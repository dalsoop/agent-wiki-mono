import Foundation
import KeychainKit
import os

/// 세션 저장소 seam. 정본은 Keychain(`KeychainSessionStore`), 테스트·러너는 `InMemorySessionStore`.
public protocol GujoSessionStore: Sendable {
    func data(account: String) -> Data?
    @discardableResult func setData(_ value: Data, account: String) -> Bool
    func delete(account: String)
}

/// 계약 §4 Keychain 자리.
public enum GujoKeychain {
    public static let service = "net.ranode.gujo"
    public static let staffAccount = "staff"
    public static let buyerAccount = "buyer"
}

public enum GujoSessionStores {
    public static func `default`() -> any GujoSessionStore {
        KeychainSessionStore()
    }
}

/// Keychain generic-password 저장소. `CachedKeychainStore` 위의 얇은 어댑터 —
/// 앱이 `SecItem*` 를 직접 부르지 않는다(KeychainKit 원칙).
public struct KeychainSessionStore: GujoSessionStore {
    private let store: CachedKeychainStore

    public init(service: String = GujoKeychain.service, readTimeout: TimeInterval = 2.0) {
        store = CachedKeychainStore(service: service, readTimeout: readTimeout)
    }

    public func data(account: String) -> Data? { store.data(account: account) }

    @discardableResult
    public func setData(_ value: Data, account: String) -> Bool {
        store.setData(value, account: account)
    }

    public func delete(account: String) { store.delete(account: account) }
}

/// 인메모리 저장소 — 테스트와 Keychain 이 없는 환경(CI 러너) 용.
public final class InMemorySessionStore: GujoSessionStore, Sendable {
    private let memory: OSAllocatedUnfairLock<[String: Data]>

    public init(initial: [String: Data] = [:]) {
        memory = OSAllocatedUnfairLock(initialState: initial)
    }

    public func data(account: String) -> Data? {
        memory.withLock { $0[account] }
    }

    @discardableResult
    public func setData(_ value: Data, account: String) -> Bool {
        memory.withLock { $0[account] = value }
        return true
    }

    public func delete(account: String) {
        memory.withLock { _ = $0.removeValue(forKey: account) }
    }

    public var accounts: [String] { memory.withLock { $0.keys.sorted() } }
}

extension GujoSessionStore {
    func load<Value: Decodable>(_ type: Value.Type, account: String) -> Value? {
        guard let data = data(account: account) else { return nil }
        do {
            return try SessionCoding.decoder.decode(type, from: data)
        } catch {
            return nil
        }
    }

    @discardableResult
    func save<Value: Encodable>(_ value: Value, account: String) -> Bool {
        do {
            return setData(try SessionCoding.encoder.encode(value), account: account)
        } catch {
            return false
        }
    }
}

/// 세션 JSON 인코딩 규약 — 날짜는 ISO-8601, 키는 snake_case(서버 JSON 과 같은 모양).
enum SessionCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(ISO8601Dates.decode)
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}

/// 서버가 `2026-12-09T00:00:00Z` 도, 소수초 붙은 형태도 줄 수 있어 둘 다 받는다.
enum ISO8601Dates {
    // `Date.ISO8601FormatStyle` 은 값 타입(Sendable)이라 Swift 6 전역 상태 검사에 걸리지 않는다.
    private static let plain = Date.ISO8601FormatStyle()
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func parse(_ text: String) -> Date? {
        do {
            return try plain.parse(text)
        } catch {
            do {
                return try fractional.parse(text)
            } catch {
                return nil
            }
        }
    }

    static func decode(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = parse(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "ISO-8601 날짜가 아님: \(text)")
        }
        return date
    }
}
