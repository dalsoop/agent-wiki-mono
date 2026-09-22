import Foundation

/// Codable 값을 JSON 파일에 원자적으로 저장/로드하는 제네릭 store.
///
/// ~16개 앱이 같은 알고리즘을 복붙했다 —
/// load: `Data(contentsOf:) → JSONDecoder.decode`, 실패 시 기본값;
/// save: `createDirectory(withIntermediateDirectories:) → JSONEncoder([.prettyPrinted,.sortedKeys]) → write(.atomic)`.
/// 이 타입이 그 정본이다. 앱은 URL(보통 `AppPaths.stateFile`)과 값 타입만 정한다.
public struct JSONStateStore<Value: Codable>: Sendable {
    public let url: URL
    public let dateCoding: JSONDateCoding

    public init(url: URL, dateCoding: JSONDateCoding = .deferred) {
        self.url = url
        self.dateCoding = dateCoding
    }

    /// Date 를 ISO-8601 문자열로 쓰는 캐시·리포트 파일용.
    public static func iso8601(url: URL) -> JSONStateStore<Value> {
        JSONStateStore(url: url, dateCoding: .iso8601)
    }

    /// 파일이 없거나 디코드 실패면 `defaultValue()` 를 돌려준다(관대한 로드).
    /// 파일이 디스크에 존재하지만 디코드에 실패한 경우 `backupCorrupt == true`이면
    /// 즉시 원본 손상 파일을 `url.path + ".corrupt." + timestamp` 경로로 복사 격리(quarantine)하고
    /// stderr에 경고를 출력한 후 `defaultValue()`를 반환한다.
    public func load(default defaultValue: @autoclosure () -> Value, backupCorrupt: Bool = true) -> Value {
        do {
            guard let value = try loadIfPresent() else {
                return defaultValue()
            }
            return value
        } catch {
            if backupCorrupt {
                handleCorruptBackup(error: error)
            }
            return defaultValue()
        }
    }

    private func handleCorruptBackup(error: Error) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let quarantinedURL = quarantineCorruptedFile(at: url)
        let message = "[AppPathsKit.JSONStateStore] Warning: Failed to decode state file at \(url.path), quarantined to \(quarantinedURL?.path ?? "unknown"). Error: \(error)\n"
        guard let data = message.data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }

    /// 파일이 없거나 디코드 실패 시 throw(엄격 로드).
    public func loadStrict() throws -> Value {
        guard let value = try loadIfPresent() else {
            throw JSONStateStoreError.fileNotFound(url)
        }
        return value
    }

    /// 손상된 파일을 `url.path + ".corrupt." + timestamp` 경로로 복사 격리(quarantine)한다.
    @discardableResult
    public func quarantineCorruptedFile(at targetURL: URL) -> URL? {
        Self.quarantineCorruptedFile(at: targetURL)
    }

    /// 현재 store URL의 손상된 파일을 복사 격리(quarantine)한다.
    @discardableResult
    public func quarantineCorruptedFile() -> URL? {
        Self.quarantineCorruptedFile(at: url)
    }

    /// 손상된 파일을 `url.path + ".corrupt." + timestamp` 경로로 복사 격리(quarantine)한다.
    @discardableResult
    public static func quarantineCorruptedFile(at url: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let timestamp = Int(Date().timeIntervalSince1970)
        var destinationURL = URL(fileURLWithPath: "\(url.path).corrupt.\(timestamp)")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            destinationURL = URL(fileURLWithPath: "\(url.path).corrupt.\(timestamp).\(DispatchTime.now().uptimeNanoseconds)")
        }
        do {
            try FileManager.default.copyItem(at: url, to: destinationURL)
            return destinationURL
        } catch {
            let message = "[AppPathsKit.JSONStateStore] Failed to quarantine corrupt file at \(url.path): \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
            return nil
        }
    }

    /// 파일이 없으면 nil, 있으면 디코드(디코드 오류는 throw) — 엄격 로드가 필요할 때.
    public func loadIfPresent() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder().decode(Value.self, from: data)
    }

    /// 상위 디렉터리를 만들고 pretty/sorted JSON 을 원자적으로 쓴다.
    /// 대상 URL이 심볼릭 링크인 경우 심링크 노드를 파괴하지 않고 물리 대상 경로에 안전하게 원자적 저장한다.
    public func save(_ value: Value) throws {
        let resolvedURL = url.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(
            at: resolvedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder().encode(value).write(to: resolvedURL, options: .atomic)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateCoding.decodingStrategy
        return decoder
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = dateCoding.encodingStrategy
        return encoder
    }
}

/// `JSONEncoder.DateEncodingStrategy` 는 Sendable 이 아니라 store 가 이걸 든다.
public enum JSONDateCoding: Sendable {
    case deferred
    case iso8601

    var encodingStrategy: JSONEncoder.DateEncodingStrategy {
        switch self {
        case .deferred: return .deferredToDate
        case .iso8601: return .iso8601
        }
    }

    var decodingStrategy: JSONDecoder.DateDecodingStrategy {
        switch self {
        case .deferred: return .deferredToDate
        case .iso8601: return .iso8601
        }
    }
}

// MARK: - JSONStateStore Error

public enum JSONStateStoreError: LocalizedError, Equatable, Sendable {
    case fileNotFound(URL)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "파일이 존재하지 않습니다: \(url.path)"
        }
    }
}

// MARK: - Top-level Helper

/// 손상된 파일을 `url.path + ".corrupt." + timestamp` 경로로 복사 격리(quarantine)하는 편의 헬퍼.
@discardableResult
public func quarantineCorruptedFile(at url: URL) -> URL? {
    JSONStateStore<EmptyCorruptStatePlaceholder>.quarantineCorruptedFile(at: url)
}

private struct EmptyCorruptStatePlaceholder: Codable {}

