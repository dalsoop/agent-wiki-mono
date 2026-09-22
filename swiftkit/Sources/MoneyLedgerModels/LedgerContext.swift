import Foundation

/// 사업/개인 — 앱 하나당 scope 하나. 데이터 루트·상태미러 이름·Vault 네임스페이스가 갈린다.
public enum LedgerScope: String, Codable, Sendable, CaseIterable {
    case business
    case personal

    public var appName: String {
        switch self {
        case .business: "BusinessLedger"
        case .personal: "PersonalLedger"
        }
    }

    public var slug: String {
        switch self {
        case .business: "business-ledger"
        case .personal: "personal-ledger"
        }
    }

    public func label(korean: Bool) -> String {
        switch self {
        case .business: korean ? "사업" : "business"
        case .personal: korean ? "개인" : "personal"
        }
    }
}

/// 앱 실행 문맥 — GUI·CLI 가 같은 값으로 만들어 같은 원장을 본다.
public struct LedgerContext: Sendable {
    public let scope: LedgerScope
    /// 원장 sqlite 경로. 기본 ~/Library/Application Support/<AppName>/ledger.sqlite.
    public let databaseURL: URL

    public init(scope: LedgerScope, databaseURL: URL) {
        self.scope = scope
        self.databaseURL = databaseURL
    }

    private static func databaseURLFromEnvironment(
        scope: LedgerScope,
        environment: [String: String]
    ) -> URL? {
        guard let directPath = environment["MONEY_LEDGER_SQLITE_PATH"], !directPath.isEmpty else {
            guard let root = environment[homeOverrideKey(scope: scope)], !root.isEmpty else {
                guard let stateRoot = environment["SWIFT_APP_STATE_ROOT"], !stateRoot.isEmpty else {
                    return nil
                }
                let base = URL(fileURLWithPath: stateRoot, isDirectory: true)
                    .appendingPathComponent("Library/Application Support/\(scope.appName)", isDirectory: true)
                return base.appendingPathComponent("ledger.sqlite")
            }
            return URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("ledger.sqlite")
        }
        return URL(fileURLWithPath: directPath)
    }

    /// 표준 문맥. 테스트/격리는 MONEY_FLOW_<SCOPE>_HOME 환경변수로 루트를 바꾼다
    /// (pim-calendar 의 PIM_CALENDAR_HOME 관례).
    public static func standard(
        scope: LedgerScope,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LedgerContext {
        if let url = databaseURLFromEnvironment(scope: scope, environment: environment) {
            return LedgerContext(scope: scope, databaseURL: url)
        }
        #if os(macOS)
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(scope.appName)", isDirectory: true)
        #else
        let base = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support"))
            .appendingPathComponent(scope.appName, isDirectory: true)
        #endif
        return LedgerContext(scope: scope, databaseURL: base.appendingPathComponent("ledger.sqlite"))
    }

    public static func homeOverrideKey(scope: LedgerScope) -> String {
        switch scope {
        case .business: "BUSINESS_LEDGER_HOME"
        case .personal: "PERSONAL_LEDGER_HOME"
        }
    }

    /// Vault 마스터 비밀번호 환경변수(에이전트/무인 경로). env-vault 의 ENVVAULT_MASTER_PASSWORD 관례.
    public var masterPasswordEnvKey: String {
        switch scope {
        case .business: "BUSINESS_LEDGER_MASTER_PASSWORD"
        case .personal: "PERSONAL_LEDGER_MASTER_PASSWORD"
        }
    }

    /// 앱별 Vault 세션 Keychain 서비스 — vaultwarden-client 본체와 분리된 자체 로그인 상태.
    public var vaultKeychainService: String {
        "net.ranode.\(scope.slug).vault"
    }

    /// Vaultwarden Secure Note 이름 네임스페이스.
    public func vaultNoteName(entity: String, id: String) -> String {
        "ledger/\(scope.rawValue)/\(entity)/\(id)"
    }

    /// StateMirror 게시 이름(~/.swift-app-state/<slug>.json).
    public var stateMirrorApp: String { scope.slug }
}
