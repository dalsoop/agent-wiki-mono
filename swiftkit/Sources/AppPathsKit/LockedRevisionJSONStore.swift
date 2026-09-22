import Foundation

public protocol RevisionedJSON: Codable, Sendable {
    var revision: UInt64 { get set }
}

public enum LockedJSONStoreError: LocalizedError, Equatable {
    case unreadable(String)
    case conflict(expected: UInt64, actual: UInt64)
    case lockFailed

    public var errorDescription: String? {
        switch self {
        case .unreadable(let detail):
            "설정 파일을 읽을 수 없습니다. 원본을 보존했습니다: \(detail)"
        case .conflict(let expected, let actual):
            "다른 프로세스가 설정을 변경했습니다(revision \(expected) → \(actual)). 다시 불러온 뒤 재시도하세요."
        case .lockFailed:
            "설정 파일 잠금을 얻지 못했습니다."
        }
    }
}

/// flock + revision 낙관적 동시성 JSON 파일. JSONStateStore 는 잠금·revision 이 없다.
public struct LockedRevisionJSONStore<Value: RevisionedJSON>: Sendable {
    public let url: URL
    private let makeDefault: @Sendable () -> Value

    public init(url: URL, default defaultValue: @autoclosure @escaping @Sendable () -> Value) {
        self.url = url
        self.makeDefault = defaultValue
    }

    public func load() throws -> Value {
        try withLock(shared: true) { try loadUnlocked() }
    }

    public func save(
        _ config: inout Value,
        beforeWrite: () throws -> Void = {},
        rollbackBeforeWrite: () -> Void = {},
        afterWrite: () -> Void = {}
    ) throws {
        try withLock(shared: false) {
            let current = try loadUnlocked()
            guard current.revision == config.revision else {
                throw LockedJSONStoreError.conflict(
                    expected: config.revision, actual: current.revision)
            }
            var next = config
            next.revision += 1
            do {
                try beforeWrite()
                let enc = JSONEncoder()
                enc.outputFormatting = [.prettyPrinted, .sortedKeys]
                try enc.encode(next).write(to: url, options: .atomic)
            } catch {
                rollbackBeforeWrite()
                throw error
            }
            config = next
            afterWrite()
        }
    }

    private func loadUnlocked() throws -> Value {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return makeDefault()
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            throw LockedJSONStoreError.unreadable(error.localizedDescription)
        }
    }

    private func withLock<T>(shared: Bool, _ body: () throws -> T) throws -> T {
        do {
            try AppPaths.ensureDirectory(
                at: url.deletingLastPathComponent(), permissions: 0o700)
        } catch {
            throw LockedJSONStoreError.unreadable("디렉터리 생성 실패: \(error.localizedDescription)")
        }
        let lockURL = url.appendingPathExtension("lock")
        do {
            return try FastFileLock.withLock(at: lockURL, exclusive: !shared, body)
        } catch is AppPathsError {
            throw LockedJSONStoreError.lockFailed
        }
    }
}
