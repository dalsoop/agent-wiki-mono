import Foundation

/// FastSecureLedger — 0600/0700 보안 권한과 fsync(2) 원자적 영속화를 보장하는 표준 레저(원장) 엔진.
///
/// 모노레포 전역(LoginStore, TenantStore, TaskStore, CaseStore 등)에서 개별적으로
/// 복사-붙여넣기되던 임시파일 생성, 0600 권한 부여, replaceItemAt, mutate 패턴을 단일 SSOT로 통합한다.
public final class FastSecureLedger<T: Codable & Sendable>: Sendable {
    public let fileURL: URL
    public let directoryPermissions: mode_t
    public let filePermissions: mode_t
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let defaultFactory: (@Sendable () -> T)?

    public var directoryURL: URL { fileURL.deletingLastPathComponent() }

    public init(
        fileURL: URL,
        directoryPermissions: mode_t = 0o700,
        filePermissions: mode_t = 0o600,
        encoder: JSONEncoder = {
            let e = JSONEncoder()
            e.outputFormatting = [.prettyPrinted, .sortedKeys]
            return e
        }(),
        decoder: JSONDecoder = JSONDecoder(),
        default: (@Sendable () -> T)? = nil
    ) {
        self.fileURL = fileURL
        self.directoryPermissions = directoryPermissions
        self.filePermissions = filePermissions
        self.encoder = encoder
        self.decoder = decoder
        self.defaultFactory = `default`
    }

    /// 디렉터리 존재 및 권한(기본 0700)을 보장한다.
    public func ensureDirectory() throws {
        let dir = directoryURL
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: directoryPermissions)]
            )
        }
        try fm.setAttributes([.posixPermissions: NSNumber(value: directoryPermissions)], ofItemAtPath: dir.path)
    }

    /// 원장 파일에서 데이터를 로드한다. 파일이 없으면 기본값을 반환하거나 에러를 던진다.
    public func load() throws -> T {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            if let defaultFactory {
                return defaultFactory()
            }
            throw CocoaError(.fileReadNoSuchFile)
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            if let defaultFactory {
                return defaultFactory()
            }
            throw CocoaError(.fileReadCorruptFile)
        }
        return try decoder.decode(T.self, from: data)
    }

    /// 원장 데이터를 보안 권한(기본 0600) 및 fsync(2) 보장과 함께 원자적으로 저장한다.
    public func save(_ value: T) throws {
        try ensureDirectory()
        let data = try encoder.encode(value)
        try FastAtomicWriter.writeAtomic(to: fileURL, data: data, permissions: filePermissions)
    }

    /// 읽고-수정하고-저장하는 트랜잭션 묶음.
    @discardableResult
    public func mutate<R>(_ body: (inout T) throws -> R) throws -> R {
        var current = try load()
        let result = try body(&current)
        try save(current)
        return result
    }

    /// 원장 파일 존재 여부.
    public var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// 원장 파일을 안전하게 삭제한다.
    public func delete() throws {
        if exists {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
