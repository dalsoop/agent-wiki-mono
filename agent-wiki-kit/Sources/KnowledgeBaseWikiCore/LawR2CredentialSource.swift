import CommandKit
import Darwin
import Foundation

// agent-law R2 키 출처 — 키체인(기본) 또는 Bitwarden 항목.
// 근거: docs/security.md "R2 와 세션"(키 보관 조문), 결정 0009.
// - 키체인 `agent-law-r2` 에 두 값이 있으면 그것을 쓴다(지금과 같다).
// - 없고 출처가 `bitwarden:<item id>` 면, R2 키가 꼭 필요한 명령은 시작할 때
//   `vaultwarden-client item field exec … --env <변수> -- vaultwarden-client item field exec … --env <변수> -- <자기 자신> <원래 인자>`
//   로 자신을 다시 실행한다. 값은 하위 프로세스 환경에만 들어가고 파일·화면에 남지 않는다.
// - 다시 실행된 자식만(재실행 표지가 있을 때만) 그 두 환경 변수를 받는다. 표지 없이 사람이 넣은 환경 변수는 받지 않는다.
// - 자식은 표지가 있으면 다시 실행하지 않는다(무한 재실행 방지). 받은 뒤 세 변수를 자기 환경에서 지워 손자 프로세스로 흘리지 않는다.

/// 호스트 설정 `lawStorage.credentialSource` 의 해석.
public enum LawR2CredentialSource: Equatable, Sendable, CustomStringConvertible {
    case keychain
    case bitwarden(itemID: String)

    public static let bitwardenPrefix = "bitwarden:"
    /// `world storage --credential-source none` — 출처를 지우고 키체인만 쓴다.
    public static let clearToken = "none"
    public static let optionUsage = "--credential-source bitwarden:<item id> | none"

    /// 설정 문자열 → 출처. 비었거나 없으면 키체인, 형식이 틀리면 nil.
    public init?(reference: String?) {
        let raw = reference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty || raw == "keychain" {
            self = .keychain
            return
        }
        guard raw.hasPrefix(Self.bitwardenPrefix) else { return nil }
        let item = String(raw.dropFirst(Self.bitwardenPrefix.count))
        guard Self.isValidItemID(item) else { return nil }
        self = .bitwarden(itemID: item)
    }

    /// 설정 파일에 남길 값. 키체인은 기본값이라 남기지 않는다.
    public var reference: String? {
        switch self {
        case .keychain: return nil
        case .bitwarden(let item): return Self.bitwardenPrefix + item
        }
    }

    public var description: String { reference ?? "keychain" }

    /// 항목 id 는 비밀이 아니다. 영문자·숫자·`-` 만, 128자 이내(인자 주입을 막는다).
    static func isValidItemID(_ item: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
        return !item.isEmpty && item.count <= 128 && !item.hasPrefix("-")
            && item.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// `--credential-source` 옵션 값 → 설정에 남길 값(nil = 지움). 형식이 틀리면 안내 문구.
    public static func settingValue(forOption raw: String) -> Result<String?, LawR2CredentialSourceOptionError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == clearToken || trimmed == "keychain" { return .success(nil) }
        guard trimmed.hasPrefix(bitwardenPrefix), let source = LawR2CredentialSource(reference: trimmed) else {
            return .failure(LawR2CredentialSourceOptionError(value: trimmed))
        }
        return .success(source.reference)
    }
}

public struct LawR2CredentialSourceOptionError: Error, Equatable, Sendable, CustomStringConvertible {
    public let value: String
    public var description: String {
        "키 출처 형식이 아님: '\(value)' — \(LawR2CredentialSource.optionUsage)"
    }
}

// MARK: - 재실행으로 받은 값

/// 다시 실행된 자식이 받는 값. 표지(`markerVariable`)가 있을 때만 두 환경 변수를 받는다.
public struct LawR2EnvHandoff: Sendable, Equatable {
    public static let accessKeyVariable = "AGENT_LAW_R2_ACCESS_KEY_ID"
    public static let secretKeyVariable = "AGENT_LAW_R2_SECRET_ACCESS_KEY"
    /// 재실행 표지. 값은 부모가 `execv` 직전에 발급한 일회용 표(`LawR2HandoffTicket`)다.
    public static let markerVariable = "AGENT_WIKI_R2_FROM_BITWARDEN"
    public static let variables = [markerVariable, accessKeyVariable, secretKeyVariable]

    /// 이 프로세스가 Bitwarden 을 거쳐 다시 실행된 자식인가.
    public let isReexecChild: Bool
    public let credentials: LawR2Credentials?

    public init(isReexecChild: Bool, credentials: LawR2Credentials?) {
        self.isReexecChild = isReexecChild
        self.credentials = credentials
    }

    /// 표지 없는 환경 변수는 무시한다(사람이 env 로 키를 넣는 경로는 열지 않는다).
    /// 표지 값도 손으로 세울 수 있으므로, 부모가 발급한 일회용 표를 이 프로세스가 실제로 교환했을 때만
    /// 받는다(`ticketRedeemed`). 셸 설정에 박아 둔 값은 다음 실행에서 표가 없어 거부된다.
    /// `vaultwarden-client item field exec` 는 자신을 대상 명령으로 바꿔 실행하므로(부모로 남지 않음)
    /// 부모 프로세스 확인은 쓸 수 없다(2026-10-06 실측). 근거: 결정 0009.
    public init(environment: [String: String], ticketRedeemed: Bool) {
        let child = !(environment[Self.markerVariable] ?? "").isEmpty && ticketRedeemed
        func value(_ name: String) -> String? {
            guard let raw = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
            else { return nil }
            return raw
        }
        guard child, let access = value(Self.accessKeyVariable), let secret = value(Self.secretKeyVariable) else {
            self.init(isReexecChild: child, credentials: nil)
            return
        }
        self.init(isReexecChild: true, credentials: LawR2Credentials(accessKeyID: access, secretAccessKey: secret))
    }

    /// 이 프로세스 환경에서 한 번 읽고 세 변수를 지운다 — git·AI 실행 도구 같은 하위 프로세스가 값을 물려받지 않게.
    /// CLI 진입점이 가장 먼저 읽는다(단일 인스턴스 가드보다 먼저).
    public static let current: LawR2EnvHandoff = {
        let environment = ProcessInfo.processInfo.environment
        let redeemed = environment[markerVariable].map { LawR2HandoffTicket.standard.redeem($0) } ?? false
        let handoff = LawR2EnvHandoff(environment: environment, ticketRedeemed: redeemed)
        scrubProcessEnvironment()
        return handoff
    }()

    public static func scrubProcessEnvironment() {
        for name in variables { unsetenv(name) }
    }
}

// MARK: - 일회용 표

/// 재실행 직전 부모가 발급하고 다시 실행된 자식이 한 번 교환하는 표. 사용자 전용 폴더(0700)의 빈 파일(0600)이고,
/// 이름이 표 값이다. 교환하면 지운다. 오래된 표(기본 120초)는 받지 않는다.
public struct LawR2HandoffTicket: Sendable {
    public let directory: URL
    public let maxAge: TimeInterval

    public init(directory: URL, maxAge: TimeInterval = 120) {
        self.directory = directory
        self.maxAge = maxAge
    }

    public static let standard = LawR2HandoffTicket(
        directory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("agent-wiki-r2-tickets"))

    /// 새 표를 발급하고 값을 돌려준다. 폴더·파일을 만들지 못하면 nil.
    public func issue() -> String? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return nil
        }
        let token = UUID().uuidString
        let created = fm.createFile(
            atPath: directory.appendingPathComponent(token).path, contents: Data(), attributes: [.posixPermissions: 0o600])
        return created ? token : nil
    }

    /// 표를 교환한다 — 형식이 맞고, 파일이 있고, 오래되지 않았으면 지우고 true.
    public func redeem(_ token: String, now: Date = Date()) -> Bool {
        guard UUID(uuidString: token) != nil else { return false }
        let path = directory.appendingPathComponent(token).path
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: path),
              let modified = attributes[.modificationDate] as? Date else { return false }
        let fresh = now.timeIntervalSince(modified) <= maxAge
        do {
            try fm.removeItem(atPath: path)
        } catch {
            return false
        }
        return fresh
    }
}

// MARK: - 해석(키체인 → 재실행으로 받은 값)

/// `LawR2Client.standard` 의 기본 공급자. 키체인 → 재실행으로 받은 값 → 안내와 함께 실패.
public struct LawR2CredentialResolver: LawR2CredentialProviding {
    public let source: LawR2CredentialSource
    let keychain: any LawR2CredentialProviding
    let handoff: LawR2EnvHandoff

    public init(
        source: LawR2CredentialSource,
        keychain: any LawR2CredentialProviding = LawKeychainCredentialProvider(),
        handoff: LawR2EnvHandoff = .current
    ) {
        self.source = source
        self.keychain = keychain
        self.handoff = handoff
    }

    public func credentials() throws -> LawR2Credentials {
        let keychainError: any Error
        do {
            return try keychain.credentials()
        } catch {
            keychainError = error
        }
        if let received = handoff.credentials { return received }
        if handoff.isReexecChild { throw LawR2CredentialError.bitwardenHandoffEmpty }
        if case .bitwarden(let item) = source { throw LawR2CredentialError.bitwardenNotReexecuted(itemID: item) }
        throw keychainError
    }
}

// MARK: - 재실행 계획

/// R2 키가 꼭 필요한 명령의 시작에서 Bitwarden 을 거쳐 자신을 다시 실행할지 정한다. 실행(`execv`)은 CLI 층이 한다.
public enum LawR2BitwardenReexec {
    public static let clientName = "vaultwarden-client"

    public struct Plan: Equatable, Sendable {
        /// `execv` 할 실행 파일 절대 경로(PATH 에서 찾은 vaultwarden-client).
        public let program: String
        public let argv: [String]
    }

    public enum Decision: Equatable, Sendable {
        /// 다시 실행하지 않는다(키가 필요 없는 명령, 키체인에 값이 있음, 출처 미설정, 이미 다시 실행된 자식 등).
        case proceed
        case reexec(Plan)
        case failure(String)
    }

    /// R2 키 없이는 할 일이 없는 명령인가(선두 전역 옵션을 뗀 인자).
    /// `summon`·`enact` 의 R2 읽기·올리기는 키가 없으면 그 단계만 건너뛰므로 넣지 않는다.
    public static func requiresCredentials(_ arguments: [String], file: BoundLedgerFile) -> Bool {
        guard let command = arguments.first, !arguments.contains("--help"), !arguments.contains("-h") else {
            return false
        }
        switch command {
        case "archive": return !arguments.contains("--dry-run")
        case "redact", "sync": return true
        case "dream":
            // 드리밍 기기에서만 실제로 돈다. 다른 기기의 예약 틱은 조용히 끝나므로 금고를 열지 않는다.
            guard arguments.dropFirst().first == "run", let device = file.currentDevice, !device.isEmpty else {
                return false
            }
            return file.dreamDevice == device
        default: return false
        }
    }

    /// - Parameters:
    ///   - command: 선두 `--as`·`--world` 를 뗀 인자(명령부터).
    ///   - originalArguments: 실행 파일 이름을 뺀 원래 인자 전부. 자식에게 그대로 넘긴다.
    ///   - executable: 이 실행 파일의 절대 경로.
    ///   - locate: 실행 파일 이름 → 절대 경로(PATH 해석). 시험은 주입한다.
    public static func decide(
        command: [String], originalArguments: [String], file: BoundLedgerFile,
        keychain: any LawR2CredentialProviding, handoff: LawR2EnvHandoff,
        executable: String?, locate: (String) -> String?
    ) -> Decision {
        guard requiresCredentials(command, file: file) else { return .proceed }
        let settings = file.lawStorage ?? LawStorageSettings()
        // 엔드포인트가 없으면 명령이 "R2 엔드포인트 미설정" 으로 먼저 끝난다. 금고를 열 이유가 없다.
        guard settings.resolvedEndpoint != nil else { return .proceed }
        guard case .bitwarden(let item) = settings.resolvedCredentialSource else { return .proceed }
        // 이미 다시 실행된 자식은 다시 실행하지 않는다. 값이 비었으면 해석기가 안내와 함께 실패한다.
        guard !handoff.isReexecChild else { return .proceed }
        if (try? keychain.credentials()) != nil { return .proceed }
        guard let executable, executable.hasPrefix("/") else {
            return .failure("R2 키를 Bitwarden 에서 받으려 했지만 이 실행 파일의 절대 경로를 알 수 없음")
        }
        guard let client = locate(clientName) else {
            return .failure(
                "R2 키를 Bitwarden(\(LawR2CredentialSource.bitwarden(itemID: item))) 에서 받으려 했지만 PATH 에 "
                    + "\(clientName) 가 없음 — 설치하거나 키체인 서비스 '\(LawKeychainCredentialProvider.service)' 에 넣으세요")
        }
        return .reexec(Plan(
            program: client,
            argv: argv(client: client, itemID: item, executable: executable, originalArguments: originalArguments)))
    }

    /// 두 겹 `item field exec`: 바깥이 접근 키, 안쪽이 비밀 키를 하위 프로세스 환경에 넣고 마지막에 자신을 실행한다.
    public static func argv(client: String, itemID: String, executable: String, originalArguments: [String]) -> [String] {
        func layer(_ field: String, _ variable: String) -> [String] {
            [client, "item", "field", "exec", itemID, "field:\(field)", "--env", variable, "--"]
        }
        return layer(LawKeychainCredentialProvider.accessKeyAccount, LawR2EnvHandoff.accessKeyVariable)
            + layer(LawKeychainCredentialProvider.secretKeyAccount, LawR2EnvHandoff.secretKeyVariable)
            + [executable] + originalArguments
    }

    /// PATH 해석. 하위 프로세스 PATH 관례(`LawGitSync`)와 같이 PATH 뒤에 Homebrew·`/usr/local/bin` 을 더 본다.
    public static func locate(
        _ program: String, environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        if program.contains("/") { return isExecutable(program) ? program : nil }
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + HostPlatformPaths.standardBinPaths
        for directory in directories where directory.hasPrefix("/") {
            let candidate = (directory as NSString).appendingPathComponent(program)
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }
}
