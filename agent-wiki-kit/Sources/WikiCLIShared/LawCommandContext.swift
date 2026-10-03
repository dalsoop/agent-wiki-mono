import Foundation
import KnowledgeBaseWikiCore
import WikiLedgerKit

/// ledger 2 원장 쓰기에 각 CLI 가 덧붙이는 검사·문구(전역 CLI 의 repo 쓰기 권한 검사 등).
public struct LedgerTwoWriteHooks {
    /// 쓰기 전에 부른다. 거부면 스스로 `fail` 한다.
    public var checkWritePermission: () -> Void
    public var publishCopy: WorldAwarePublishCopy

    public init(checkWritePermission: @escaping () -> Void = {}, publishCopy: WorldAwarePublishCopy) {
        self.checkWritePermission = checkWritePermission
        self.publishCopy = publishCopy
    }
}

/// 두 CLI(전역·repo)가 새 명령 표면에 넘기는 문맥. 자리만 둔 명령(뒤 작업)도 이것만 받는다.
public struct LawCommandContext {
    public let author: String
    public let worldOverride: String?
    /// 해석된 원장. 원장 없이 도는 명령(`hook session`)에서는 nil 일 수 있다.
    public let world: LedgerWorld?
    public let config: LedgerConfig
    public let file: BoundLedgerFile
    public let catalog: WorldBindingCatalog
    public let environment: [String: String]
    public let repository: RepositoryIdentity?
    public let ledgerTwo: LedgerTwoWriteHooks

    public init(
        author: String, worldOverride: String?, world: LedgerWorld?, config: LedgerConfig,
        file: BoundLedgerFile, catalog: WorldBindingCatalog,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        repository: RepositoryIdentity? = nil, ledgerTwo: LedgerTwoWriteHooks
    ) {
        self.author = author
        self.worldOverride = worldOverride
        self.world = world
        self.config = config
        self.file = file
        self.catalog = catalog
        self.environment = environment
        self.repository = repository
        self.ledgerTwo = ledgerTwo
    }

    public func requireWorld() -> LedgerWorld {
        guard let world else { fail("원장을 정할 수 없음 — --world <이름> 을 명령 앞에 주세요") }
        return world
    }

    public var root: URL { URL(fileURLWithPath: requireWorld().rootPath) }

    /// 대상 원장이 ledger 3 인가. 판정은 설정의 원장 키·전신(`WorldBindingCatalog.isLedgerThree`) 하나다.
    public var isLedgerThree: Bool {
        guard let world else { return false }
        return catalog.isLedgerThree(world.name)
    }

    public var ledgerStore: LedgerStore { LedgerStore(root: root) }

    public func lawTarget() -> LawLedgerTarget {
        let world = requireWorld()
        return LawLedgerTarget(
            worldName: world.name, root: URL(fileURLWithPath: world.rootPath), catalog: catalog,
            registeredDevices: file.devices ?? [], currentDevice: file.currentDevice)
    }

    public func scopeIndex() -> LawScopeIndex { LawScopeIndex(current: requireWorld().name, catalog: catalog) }

    /// 공포 주체. 작성자 종류는 `--as`/기본 작성자 접두어, 모델 기록은 `LawModelRecordSource.collect`.
    public func actor(explicit: LawModelRecord) -> LawActor {
        do {
            return try LawActorResolution.actor(
                author: author, explicit: explicit, environment: environment, device: file.currentDevice)
        } catch {
            fail("\(error)")
        }
    }
}

// MARK: - 명령 인자

/// 새 명령의 인자 파서. 모르는 옵션·값 없는 옵션은 사용법 오류(종료 코드 64).
public struct LawOptions {
    public var positionals: [String] = []
    public var values: [String: [String]] = [:]
    public var flags: Set<String> = []

    public func value(_ name: String) -> String? { values[name]?.last }
    public func all(_ name: String) -> [String] { values[name] ?? [] }
    public func has(_ name: String) -> Bool { flags.contains(name) }

    /// 모델 기록 명시 인자.
    public var modelRecord: LawModelRecord {
        LawModelRecord(
            runtime: value("--runtime"), runtimeVersion: value("--runtime-version"), model: value("--model"),
            effort: value("--effort"), app: value("--app"), appVersion: value("--app-version"))
    }

    public static let modelOptions: Set<String> = [
        "--runtime", "--runtime-version", "--model", "--effort", "--app", "--app-version",
    ]

    /// - Parameters:
    ///   - arguments: 명령 이름부터(첫 원소는 건너뛴다). `skip` 으로 하위 명령 단어 수를 더 건너뛴다.
    public static func parse(
        _ arguments: [String], skip: Int = 1, valued: Set<String>, flags: Set<String> = ["--json", "-j"],
        usage: String
    ) -> LawOptions {
        var parsed = LawOptions()
        var index = skip
        while index < arguments.count {
            let token = arguments[index]
            if flags.contains(token) {
                parsed.flags.insert(token == "-j" ? "--json" : token)
                index += 1
            } else if valued.contains(token) {
                guard index + 1 < arguments.count else { usageFail("\(token) 에 값이 없음\n\(usage)") }
                parsed.values[token, default: []].append(arguments[index + 1])
                index += 2
            } else if token.hasPrefix("--") || (token.hasPrefix("-") && token.count > 1) {
                usageFail("모르는 옵션: \(token)\n\(usage)")
            } else {
                parsed.positionals.append(token)
                index += 1
            }
        }
        return parsed
    }
}

/// 사용법 오류·폐지된 명령 — 종료 코드 64.
public func usageFail(_ message: String) -> Never {
    fail(message, code: 64)
}

/// 표준 입력 본문.
func readStandardInputBody() -> String {
    String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

/// 공포류 출력 — 표준 출력에 id 한 줄(또는 `--json` 봉투).
func printEnacted(_ ids: [String], asJSON: Bool) {
    if asJSON {
        struct Envelope: Encodable { let ok: Bool; let result: Result }
        struct Result: Encodable { let ids: [String] }
        printJSON(Envelope(ok: true, result: Result(ids: ids)))
    } else {
        for id in ids { print(id) } // allow:debug — 공포류 표준 출력은 id 한 줄
    }
}

/// 공포 경로 오류 → 거부(종료 코드 1).
func lawFail(_ error: Error) -> Never {
    fail("\(error)")
}
