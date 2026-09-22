import StateRootKit
import Foundation
import KeychainKit

/// 로컬 라이선스 키 지갑 한 줄. 키 원문은 Keychain 에만 둔다.
public struct LicenseWalletEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: String { productService }
    /// 앱 Keychain service / Bundle-style id. 예: `net.ranode.devclean`
    public var productService: String
    public var displayName: String
    public var licenseKey: String
    public var note: String
    public var updatedAt: Date

    public init(
        productService: String,
        displayName: String,
        licenseKey: String,
        note: String = "",
        updatedAt: Date = Date()
    ) {
        self.productService = productService.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.licenseKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = note
        self.updatedAt = updatedAt
    }

    /// UI 표시용 마스킹(끝 4자만).
    public var maskedKey: String {
        let k = licenseKey
        guard k.count > 4 else { return "••••" }
        return String(repeating: "•", count: max(4, k.count - 4)) + String(k.suffix(4))
    }
}

/// 제품별 라이선스 키 로컬 지갑(SSOT 발급처가 아님 — 보관·재사용만).
/// 후속 표면은 Cloud Apps 기기 탭 / `LicenseCacheKit.LicenseKeyVault`.
/// Keychain service 정본은 `keychainService` (퇴역 지갑 앱과 동일 계약, 값 변경 금지).
/// account: `entries-v1` → JSON 배열
public enum LocalLicenseWallet {
    private static let retiredWalletSlug = ["license", "key", "wallet"].joined(separator: "-")
    public static let keychainService = ["net", "ranode", retiredWalletSlug].joined(separator: ".")
    public static let account = "entries-v1"

    /// 운영 도구 Bundle ID (게이트 딥링크).
    public static let entitlementManagerBundleID = "net.ranode.license-entitlement-manager"
    public static let walletAppBundleID = ["net", "ranode", retiredWalletSlug].joined(separator: ".")

    /// 프로세스당 1개 — computed store 는 캐시가 매번 비어 Keychain 을 반복 친다.
    /// `readTimeout: 0` = 호출 스레드에서 동기 SecItem (타임아웃 오탐·세마포어 함정 제거).
    /// 지갑 조회가 게이트 경로의 정본이라 "빨리 빈 목록 오진"보다 정확한 읽기가 우선이다.
    private static let store = CachedKeychainStore(service: keychainService, readTimeout: 0)

    /// 직전 `loadAll`/`key`/`entry` 가 Keychain 타임아웃이었는지.
    public static var lastLoadTimedOut: Bool { store.lastReadTimedOut }

    public static func loadAll() -> [LicenseWalletEntry] {
        // CLI·다른 앱이 같은 Keychain 을 바꿀 수 있다. "없음" 캐시를 붙이면
        // 게이트/지갑 GUI 가 재실행 전까지 빈 목록으로 고정된다.
        store.invalidate(account: account)
        guard let data = store.data(account: account) else { return [] }
        // 빈 배열 `[]` 은 정상(키 0개). 타임아웃 nil 과 구분하기 위해 isEmpty 로 실패 처리하지 않는다.
        if data.isEmpty { return [] }
        guard let decoded = try? JSONDecoder().decode([LicenseWalletEntry].self, from: data)
        else { return [] }
        return decoded.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// 꼬인 Keychain 항목을 지운다. **키가 있으면 먼저 백업 파일을 남긴다.**
    /// 타임아웃 오탐 복구 용으로 쓰면 안 된다 — 호출 전에 `lastLoadTimedOut` 을 확인할 것.
    @discardableResult
    public static func resetCorruptStore() -> Bool {
        // 가능하면 삭제 전 스냅샷(복구 단서). 타임아웃이면 백업 실패해도 삭제는 진행.
        if let data = store.data(account: account), !data.isEmpty {
            #if os(macOS)
            let dir = URL(fileURLWithPath: StateRootKit.path(".swift-app-state/\(retiredWalletSlug)-backups"), isDirectory: true)
            #else
            let dir = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask)[0]
                .appendingPathComponent("\(retiredWalletSlug)-backups", isDirectory: true)
            #endif
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let url = dir.appendingPathComponent("entries-v1-\(stamp).json")
                try data.write(to: url, options: .atomic)
            } catch {
                // 백업 실패해도 삭제는 진행하는 의도적 정책 — 단, 복구 단서 소실은 남긴다.
                FileHandle.standardError.write(Data("license-wallet: backup failed: \(error.localizedDescription)\n".utf8))
            }
        }
        store.delete(account: account)
        store.invalidate()
        return true
    }

    public static func key(for productService: String) -> String? {
        let id = productService.trimmingCharacters(in: .whitespacesAndNewlines)
        return loadAll().first { $0.productService == id }?.licenseKey
    }

    public static func entry(for productService: String) -> LicenseWalletEntry? {
        let id = productService.trimmingCharacters(in: .whitespacesAndNewlines)
        return loadAll().first { $0.productService == id }
    }

    public static func upsert(_ entry: LicenseWalletEntry) throws {
        guard !entry.productService.isEmpty, !entry.licenseKey.isEmpty else {
            throw LicenseProviderError.configuration("productService 와 licenseKey 가 필요합니다.")
        }
        var all = loadAll()
        if let i = all.firstIndex(where: { $0.productService == entry.productService }) {
            all[i] = entry
        } else {
            all.append(entry)
        }
        try saveAll(all)
    }

    public static func delete(productService: String) throws {
        let id = productService.trimmingCharacters(in: .whitespacesAndNewlines)
        var all = loadAll()
        all.removeAll { $0.productService == id }
        try saveAll(all)
    }

    private static func saveAll(_ entries: [LicenseWalletEntry]) throws {
        let data = try JSONEncoder().encode(entries)
        store.setData(data, account: account)
    }
}

#if canImport(AppKit)
import AppKit

/// 판매/운영 도구 실행 헬퍼.
public enum LicenseOperatorLauncher {
    @discardableResult
    public static func openApplication(bundleIdentifier: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config)
        return true
    }

    @discardableResult
    public static func openEntitlementManager() -> Bool {
        openApplication(bundleIdentifier: LocalLicenseWallet.entitlementManagerBundleID)
    }

    @discardableResult
    public static func openKeyWallet() -> Bool {
        openApplication(bundleIdentifier: LocalLicenseWallet.walletAppBundleID)
    }

    @discardableResult
    public static func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}
#endif
