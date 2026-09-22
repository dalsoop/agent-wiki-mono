import Foundation
import KeychainKit

/// 앱 설치별 기기 ID — **파일 SSOT** (Keychain 아님).
///
/// 배경: fleet 앱마다 `KeychainLicenseDeviceStore(service: "net.ranode.*")` 로
/// `license-device` 항목을 하나씩 만들면 (실측 ~86개) 재서명·재설치마다
/// macOS 키체인 Allow/암호 입력이 **앱 수만큼** 반복된다. 기기 ID 는 비밀이 아니라
/// 재설치 안정용 난수 UUID 이므로 login keychain 에 둘 이유가 없다.
///
/// 경로: `~/Library/Application Support/net.ranode.license-devices/<service-safe>.id`
/// - 값은 UUID 문자열 한 줄, 모드 0600
/// - 구 Keychain 항목이 있으면 **한 번** 읽어 파일로 옮기고 이후 Keychain 을 쓰지 않는다
public struct FileLicenseDeviceStore: Sendable {
    public static let directoryName = "net.ranode.license-devices"
    public static var defaultDisplayName: String {
        #if os(macOS)
        return Host.current().localizedName ?? "This Mac"
        #else
        return "This Device"
        #endif
    }

    private let service: String
    private let fileURL: URL

    public init(service: String, baseDirectory: URL? = nil) {
        self.service = service
        let base = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Self.directoryName, isDirectory: true)
        let safe = Self.safeFileName(service)
        self.fileURL = base.appendingPathComponent("\(safe).id", isDirectory: false)
    }

    public func loadOrCreate(displayName: String = FileLicenseDeviceStore.defaultDisplayName) -> LicenseDevice {
        if let id = readFile(), !id.isEmpty {
            return LicenseDevice(identifier: id, displayName: displayName)
        }
        // 1회 마이그레이션: 구 per-app Keychain 항목 (실패해도 프롬프트 없이 새 UUID)
        if let legacy = readLegacyKeychainQuietly(), !legacy.isEmpty {
            _ = writeFile(legacy)
            return LicenseDevice(identifier: legacy, displayName: displayName)
        }
        let identifier = UUID().uuidString.lowercased()
        _ = writeFile(identifier)
        return LicenseDevice(identifier: identifier, displayName: displayName)
    }

    /// 테스트·진단용. 파일에 있는 값만 (없으면 nil).
    public func peek() -> String? { readFile() }

    public var storageURL: URL { fileURL }

    // MARK: - file IO

    private func readFile() -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    @discardableResult
    private func writeFile(_ identifier: String) -> Bool {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try identifier.write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return true
        } catch {
            return false
        }
    }

    /// Keychain 조회는 interactionNotAllowed 경로(CachedKeychainStore) — UI 프롬프트 안 띄움.
    /// 읽기 실패 시 nil (새 UUID 발급). 성공 시에만 파일로 이관.
    private func readLegacyKeychainQuietly() -> String? {
        let store = CachedKeychainStore(service: service, readTimeout: 0.5)
        return store.string(account: "license-device")
    }

    private static func safeFileName(_ service: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let mapped = service.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let s = String(mapped)
        return s.isEmpty ? "unknown" : s
    }
}
