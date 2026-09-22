import Foundation
import KeychainKit

public protocol LicenseRecordStoring: Sendable {
    func load() throws -> LicenseRecord?
    func save(_ record: LicenseRecord) throws
    func delete() throws
}

/// 라이선스 키와 활성화 ID를 generic-password Keychain 항목 하나에 저장한다.
public struct KeychainLicenseRecordStore: LicenseRecordStoring {
    private let keychain: CachedKeychainStore
    private let account: String

    public init(service: String, account: String = "primary-license") {
        keychain = CachedKeychainStore(service: service)
        self.account = account
    }

    public func load() throws -> LicenseRecord? {
        guard let data = keychain.data(account: account) else { return nil }
        return try JSONDecoder().decode(LicenseRecord.self, from: data)
    }

    public func save(_ record: LicenseRecord) throws {
        keychain.setData(try JSONEncoder().encode(record), account: account)
    }

    public func delete() throws {
        keychain.delete(account: account)
    }
}

/// 앱 설치별 무작위 기기 ID — **호환 래퍼**.
///
/// 과거에는 Keychain `license-device` 항목을 앱마다 만들어 fleet Allow 창이 폭주했다.
/// 이제 ``FileLicenseDeviceStore`` 로 위임한다 (비밀 아닌 UUID → 파일 SSOT).
public struct KeychainLicenseDeviceStore: Sendable {
    private let service: String

    public init(service: String, account: String = "license-device") {
        // account 인자는 호환용으로만 받고 무시 (파일 스토어 고정 이름)
        _ = account
        self.service = service
    }

    public func loadOrCreate(displayName: String = FileLicenseDeviceStore.defaultDisplayName) -> LicenseDevice {
        FileLicenseDeviceStore(service: service).loadOrCreate(displayName: displayName)
    }
}

/// 테스트와 미리보기에서 쓰는 메모리 저장소.
public final class InMemoryLicenseRecordStore: @unchecked Sendable, LicenseRecordStoring {
    private let lock = NSLock()
    private var record: LicenseRecord?

    public init(record: LicenseRecord? = nil) {
        self.record = record
    }

    public func load() throws -> LicenseRecord? {
        lock.lock()
        defer { lock.unlock() }
        return record
    }

    public func save(_ record: LicenseRecord) throws {
        lock.lock()
        self.record = record
        lock.unlock()
    }

    public func delete() throws {
        lock.lock()
        record = nil
        lock.unlock()
    }
}
