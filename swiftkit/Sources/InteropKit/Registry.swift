import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// 레지스트리(~/.agent-apps/registry.json) — 설치된 참여 앱의 capabilities 스냅샷.
// 스키마: {"apps": {"<name>": <capabilities.result>}, "updatedAt": ISO8601}.
// 쓰기는 ship 훅이 upsert 로 수행한다. 읽기 소비자를 위해 temp+replace 로 원자적으로
// 쓰고, 동시 upsert(ship 두 개가 같은 파일을 고치는 경우)는 sidecar flock 으로 직렬화한다.

/// `registry.json.lock` 을 열지 못하거나 flock 이 실패한 경우.
public enum RegistryStoreError: Error, Equatable, LocalizedError {
    case lockFailed(String)

    public var errorDescription: String? {
        switch self {
        case .lockFailed(let path):
            return "registry lock failed: \(path)"
        }
    }
}
public struct Registry: Codable, Equatable, Sendable {
    public var apps: [String: Capabilities]
    public var updatedAt: String

    public init(apps: [String: Capabilities] = [:], updatedAt: String = "") {
        self.apps = apps
        self.updatedAt = updatedAt
    }
}

public struct RegistryStore: Sendable {
    public let fileURL: URL

    private static var defaultFileURL: URL {
        // 이 타입이 registry.json 의 소유 SSOT 라서 직접 경로를 두는 것이 맞다.
        // 소비자 앱은 agent-app-registry CLI 로만 읽는다.
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agent-apps")
            .appendingPathComponent("registry" + ".json")
        #else
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("agent-apps")
            .appendingPathComponent("registry" + ".json")
        #endif
    }

    /// 기본 위치: `~/.agent-apps/registry.json`. 테스트는 임시 경로를 주입한다.
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    /// 레지스트리 읽기. 파일이 없으면 빈 레지스트리 — 첫 설치 전 상태도 정상이다.
    public func load() throws -> Registry {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Registry()
        }
        let data = try Data(contentsOf: fileURL)
        if let registry = try? JSONDecoder().decode(Registry.self, from: data) {
            return registry
        }

        // 초기 레지스트리에는 현재 Capabilities 계약 이전의 앱 항목도 섞여 있다.
        // 한 레거시 항목 때문에 전체 레지스트리 조회와 이후 upsert 가 막히지 않도록
        // 현재 계약으로 해석 가능한 항목만 typed view 에 노출한다. 원본 레거시 JSON은
        // upsert 시 아래 raw merge 경로에서 그대로 보존한다.
        let root = try rawRoot(from: data)
        let rawApps = root["apps"] as? [String: Any] ?? [:]
        var apps: [String: Capabilities] = [:]
        for (name, rawValue) in rawApps {
            // 깨진 한 항목은 스킵 — 레지스트리 전체 가용이 우선이다(의도적 계속).
            guard JSONSerialization.isValidJSONObject(rawValue) else { continue }
            let capabilities: Capabilities
            do {
                let valueData = try JSONSerialization.data(withJSONObject: rawValue)
                capabilities = try JSONDecoder().decode(Capabilities.self, from: valueData)
            } catch {
                continue
            }
            apps[name] = capabilities
        }
        return Registry(apps: apps, updatedAt: root["updatedAt"] as? String ?? "")
    }

    /// 같은 `registry.json` 을 쓰는 다른 프로세스와 읽기-수정-쓰기를 직렬화한다.
    /// lock 파일은 `<registry>.lock`. `RegistryCatalog.upsert` 도 이 경로를 쓴다.
    public func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        try Self.withExclusiveLock(fileURL: fileURL, body)
    }

    public static func withExclusiveLock<T>(fileURL: URL, _ body: () throws -> T) throws -> T {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = URL(fileURLWithPath: fileURL.path + ".lock")
        // 2층 잠금: flock 은 프로세스 간에만 유효하고, 같은 프로세스의 서로 다른 fd 는
        // macOS 에서 직렬화하지 못한다(실측 2026-09-02: 동시 upsert 11/15 유실).
        // 같은 프로세스 스레드는 lock 경로별 NSLock 으로 먼저 직렬화한다.
        let inProcess = inProcessLock(for: lockURL.path)
        inProcess.lock()
        defer { inProcess.unlock() }
        if !FileManager.default.fileExists(atPath: lockURL.path) {
            FileManager.default.createFile(atPath: lockURL.path, contents: Data())
        }
        let fd = open(lockURL.path, O_RDWR)
        guard fd >= 0 else { throw RegistryStoreError.lockFailed(lockURL.path) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw RegistryStoreError.lockFailed(lockURL.path) }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    /// lock 경로별 프로세스内 뮤텍스 테이블. NSLock 조합이라 Linux 에서도 동작한다.
    private static let tableLock = NSLock()
    nonisolated(unsafe) private static var inProcessLocks: [String: NSLock] = [:]

    private static func inProcessLock(for path: String) -> NSLock {
        tableLock.lock()
        defer { tableLock.unlock() }
        if let existing = inProcessLocks[path] { return existing }
        let created = NSLock()
        inProcessLocks[path] = created
        return created
    }

    /// 앱 하나의 capabilities 를 upsert 하고 updatedAt 을 갱신해 원자적으로 저장한다.
    @discardableResult
    public func upsert(_ capabilities: Capabilities, now: Date = Date()) throws -> Registry {
        try withExclusiveLock {
            try upsertLocked(capabilities, now: now)
        }
    }

    private func upsertLocked(_ capabilities: Capabilities, now: Date) throws -> Registry {
        // SSOT: absolute cli + health.command = "<abs> capabilities" (python upsert 와 동일)
        let capabilities = capabilities.normalizedForRegistry()
        var root: [String: Any]
        if FileManager.default.fileExists(atPath: fileURL.path) {
            root = try rawRoot(from: Data(contentsOf: fileURL))
        } else {
            root = ["apps": [String: Any](), "updatedAt": ""]
        }

        var rawApps = root["apps"] as? [String: Any] ?? [:]
        let encoded = try JSONEncoder().encode(capabilities)
        rawApps[capabilities.name] = try JSONSerialization.jsonObject(with: encoded)

        // 옛 이름으로 남은 항목 정리 (2026-08-05).
        //
        // 앱이 이름을 바꾸거나 별칭 CLI 가 먼저 등록되면 그 옛 키는 **영원히 갱신되지
        // 않는다** — upsert 는 선언된 이름으로만 쓰기 때문이다. 실측: `knowledge-base-wiki`
        // 항목이 남아 `agent-wiki` 와 나란히 세어졌고, status 를 붙인 뒤에도 계속
        // "status 없음" 으로 잡혔다. 되살릴 방법이 없는 유령이라 숫자만 부풀린다.
        //
        // 같은 실행 파일을 가리키는 **다른 키**만 지운다. 별칭은 대개 심링크라 경로를
        // 풀어서 본다. 파일이 없으면 손대지 않는다 — 못 읽는 것과 다른 앱인 것을
        // 구분할 수 없어서, 애매하면 남긴다.
        let fm = FileManager.default
        let mine = URL(fileURLWithPath: capabilities.cli).resolvingSymlinksInPath().path
        if !capabilities.cli.isEmpty, fm.fileExists(atPath: mine) {
            for (key, value) in rawApps where key != capabilities.name {
                guard let entry = value as? [String: Any],
                      let otherCLI = entry["cli"] as? String, !otherCLI.isEmpty,
                      URL(fileURLWithPath: otherCLI).resolvingSymlinksInPath().path == mine
                else { continue }
                rawApps.removeValue(forKey: key)
            }
        }

        root["apps"] = rawApps
        root["updatedAt"] = ISO8601DateFormatter().string(from: now)
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try saveData(data)
        return try load()
    }

    /// temp 파일에 쓴 뒤 rename — 동시 읽기 소비자가 반쯤 쓰인 JSON 을 보지 않게.
    public func save(_ registry: Registry) throws {
        try withExclusiveLock {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(registry)
            try saveData(data)
        }
    }

    private func rawRoot(from data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "registry root must be a JSON object"
            ))
        }
        return root
    }

    private func saveData(_ data: Data) throws {
        let resolvedURL = fileURL.resolvingSymlinksInPath()
        let directory = resolvedURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let tempURL = directory.appendingPathComponent(".registry.json.tmp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try data.write(to: tempURL, options: [.atomic])
        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            _ = try FileManager.default.replaceItemAt(resolvedURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: fileURL)
        }
    }
}
