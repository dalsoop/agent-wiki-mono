import Foundation

// MARK: - AtomicDocumentStoreError

public enum AtomicDocumentStoreError: LocalizedError, Equatable, Sendable {
    case fileNotFound(URL)
    case decodingFailed(url: URL, underlying: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "파일이 존재하지 않습니다: \(url.path)"
        case .decodingFailed(let url, let underlying):
            return "파일 디코딩에 실패했습니다 (Fail-Closed, 원본 파일 보존): \(url.path) [\(underlying)]"
        }
    }
}

// MARK: - AtomicDocumentStore

/// Apple Foundation 표준 원자적 임시파일 교체(`Data.WritingOptions.atomic`)와
/// 100% Fail-Closed 정책을 보장하는 단일 정본 문서 저장소.
///
/// 디코딩 실패나 에러 발생 시 결코 조용히 빈 배열/기본값으로 덮어쓰거나 격리/삭제하지 않고,
/// 디스크의 원본 파일을 100% 그대로 보존한 채 에러를 throw합니다.
public struct AtomicDocumentStore: Sendable {
    public let dateCoding: JSONDateCoding
    public let outputFormatting: JSONEncoder.OutputFormatting

    public init(
        dateCoding: JSONDateCoding = .deferred,
        outputFormatting: JSONEncoder.OutputFormatting = [.prettyPrinted, .sortedKeys]
    ) {
        self.dateCoding = dateCoding
        self.outputFormatting = outputFormatting
    }

    public static let `default` = AtomicDocumentStore()

    public static func iso8601() -> AtomicDocumentStore {
        AtomicDocumentStore(dateCoding: .iso8601)
    }

    // MARK: - Instance Methods

    /// 지정된 URL에서 데이터를 읽어 Decodable 객체로 디코딩합니다.
    /// 파일이 없으면 `AtomicDocumentStoreError.fileNotFound`를 throw하며,
    /// 디코딩 실패 시 파일 내용을 결코 덮어쓰거나 격리/삭제하지 않고 원본을 보존한 채 throw합니다 (Fail-Closed).
    public func load<T: Decodable>(as type: T.Type, from url: URL) throws -> T {
        let resolvedURL = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            throw AtomicDocumentStoreError.fileNotFound(resolvedURL)
        }
        let data = try Data(contentsOf: resolvedURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateCoding.decodingStrategy
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw AtomicDocumentStoreError.decodingFailed(url: resolvedURL, underlying: String(describing: error))
        }
    }

    /// 지정된 URL에 Encodable 객체를 Apple Foundation 표준 원자적 교체(`options: .atomic`)로 안전하게 저장합니다.
    public func save<T: Encodable>(_ value: T, to url: URL) throws {
        let resolvedURL = url.resolvingSymlinksInPath()
        let parentURL = resolvedURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = outputFormatting
        encoder.dateEncodingStrategy = dateCoding.encodingStrategy
        let data = try encoder.encode(value)

        try data.write(to: resolvedURL, options: .atomic)
    }

    /// 지정된 URL에 임의의 원시 데이터를 Apple Foundation 표준 원자적 교체(`options: .atomic`)로 안전하게 저장합니다.
    public func saveRawData(_ data: Data, to url: URL) throws {
        let resolvedURL = url.resolvingSymlinksInPath()
        let parentURL = resolvedURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try data.write(to: resolvedURL, options: .atomic)
    }

    /// 지정된 URL에 UTF-8 문자열을 원자적으로 안전하게 저장합니다.
    public func saveRawString(_ text: String, to url: URL) throws {
        try saveRawData(Data(text.utf8), to: url)
    }

    /// FastFileLock 배타적 잠금 하에서 값을 읽고, 수정한 후 원자적으로 저장하는 안전 트랜잭션.
    /// 디코딩 실패나 바디 실행 중 에러가 발생하면 디스크 저장을 원천 차단하고 원본을 보존합니다 (Fail-Closed).
    public func mutate<T: Codable>(at url: URL, _ body: (inout T) throws -> Void) throws {
        let resolvedURL = url.resolvingSymlinksInPath()
        let lockURL = Self.lockURL(for: resolvedURL)
        try FastFileLock.withLock(at: lockURL, exclusive: true) {
            var value = try load(as: T.self, from: resolvedURL)
            try body(&value)
            try save(value, to: resolvedURL)
        }
    }

    /// 파일이 존재하지 않는 신규 생성 케이스를 위한 `mutate` 편의 오버로드.
    /// 파일이 없는 경우에만 `defaultValue()`로 시작하며,
    /// 파일이 이미 존재하는데 손상(디코딩 실패)된 경우에는 기본값으로 덮어쓰지 않고 즉시 throw합니다 (Fail-Closed).
    public func mutate<T: Codable>(
        at url: URL,
        default defaultValue: @autoclosure () -> T,
        _ body: (inout T) throws -> Void
    ) throws {
        let resolvedURL = url.resolvingSymlinksInPath()
        let lockURL = Self.lockURL(for: resolvedURL)
        try FastFileLock.withLock(at: lockURL, exclusive: true) {
            var value: T
            if !FileManager.default.fileExists(atPath: resolvedURL.path) {
                value = defaultValue()
            } else {
                value = try load(as: T.self, from: resolvedURL)
            }
            try body(&value)
            try save(value, to: resolvedURL)
        }
    }

    // MARK: - Static Convenience Methods

    public static func load<T: Decodable>(as type: T.Type, from url: URL) throws -> T {
        try `default`.load(as: type, from: url)
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try `default`.save(value, to: url)
    }

    public static func saveRawData(_ data: Data, to url: URL) throws {
        try `default`.saveRawData(data, to: url)
    }

    public static func saveRawString(_ text: String, to url: URL) throws {
        try `default`.saveRawString(text, to: url)
    }

    public static func mutate<T: Codable>(at url: URL, _ body: (inout T) throws -> Void) throws {
        try `default`.mutate(at: url, body)
    }

    public static func mutate<T: Codable>(
        at url: URL,
        default defaultValue: @autoclosure () -> T,
        _ body: (inout T) throws -> Void
    ) throws {
        try `default`.mutate(at: url, default: defaultValue(), body)
    }

    // MARK: - Bound Document Store

    /// 특정 URL 및 기본 팩토리에 바인딩된 원자적 문서 저장소.
    public struct Bound<Value: Codable>: Sendable {
        public let store: AtomicDocumentStore
        public let url: URL
        public let defaultFactory: (@Sendable () -> Value)?

        public init(
            store: AtomicDocumentStore = .default,
            url: URL,
            default defaultFactory: (@Sendable () -> Value)? = nil
        ) {
            self.store = store
            self.url = url
            self.defaultFactory = defaultFactory
        }

        public init(
            store: AtomicDocumentStore = .default,
            url: URL,
            default defaultValue: @autoclosure @escaping @Sendable () -> Value
        ) {
            self.init(store: store, url: url, default: defaultValue)
        }

        public func load() throws -> Value {
            let resolved = url.resolvingSymlinksInPath()
            if !FileManager.default.fileExists(atPath: resolved.path), let defaultFactory {
                return defaultFactory()
            }
            return try store.load(as: Value.self, from: resolved)
        }

        public func save(_ value: Value) throws {
            try store.save(value, to: url)
        }

        public func mutate(_ body: (inout Value) throws -> Void) throws {
            if let defaultFactory {
                try store.mutate(at: url, default: defaultFactory(), body)
            } else {
                try store.mutate(at: url, body)
            }
        }
    }

    public func bound<Value: Codable>(
        to url: URL,
        default defaultFactory: (@Sendable () -> Value)? = nil
    ) -> Bound<Value> {
        Bound<Value>(store: self, url: url, default: defaultFactory)
    }

    public func bound<Value: Codable>(
        to url: URL,
        default defaultValue: @autoclosure @escaping @Sendable () -> Value
    ) -> Bound<Value> {
        Bound<Value>(store: self, url: url, default: defaultValue)
    }

    public static func bound<Value: Codable>(
        to url: URL,
        default defaultFactory: (@Sendable () -> Value)? = nil
    ) -> Bound<Value> {
        Bound<Value>(store: .default, url: url, default: defaultFactory)
    }

    public static func bound<Value: Codable>(
        to url: URL,
        default defaultValue: @autoclosure @escaping @Sendable () -> Value
    ) -> Bound<Value> {
        Bound<Value>(store: .default, url: url, default: defaultValue)
    }

    // MARK: - Internal Helpers

    internal static func lockURL(for targetURL: URL) -> URL {
        let resolved = targetURL.resolvingSymlinksInPath()
        let parent = resolved.deletingLastPathComponent()
        return parent.appendingPathComponent(".\(resolved.lastPathComponent).lock")
    }
}
