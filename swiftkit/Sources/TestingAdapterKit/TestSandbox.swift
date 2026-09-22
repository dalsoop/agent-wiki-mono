import Foundation

/// 테스트 실행 중 고립된 임시 파일시스템 환경을 제공하는 테스트 샌드박스.
///
/// 테스트 전용 임시 디렉터리를 생성하며, 스코프 종료 또는 인스턴스 해제 시 자동으로 정리됩니다.
public final class TestSandbox: @unchecked Sendable {
    /// 샌드박스 루트 URL
    public let rootURL: URL
    
    /// 샌드박스 루트 경로 (POSIX 스타일)
    public var path: String {
        rootURL.path
    }
    
    /// 인스턴스 해제 시 자동 정리 여부
    public let autoCleanup: Bool
    
    private let fileManager: FileManager
    private let lock = NSLock()
    private var isCleanedUp: Bool = false

    /// 새로운 TestSandbox 인스턴스를 초기화하고 임시 디렉터리를 생성합니다.
    ///
    /// - Parameters:
    ///   - prefix: 임시 디렉터리 이름의 접두사 (기본값: `"swift-app-test"`)
    ///   - baseDirectory: 상위 디렉터리 URL. 지정하지 않으면 `/private/tmp` 또는 시스템 임시 디렉터리를 사용합니다.
    ///   - autoCleanup: `deinit` 시 자동으로 디렉터리를 삭제할지 여부 (기본값: `true`)
    ///   - fileManager: 파일 작업을 수행할 FileManager 인스턴스 (기본값: `.default`)
    public init(
        prefix: String = "swift-app-test",
        baseDirectory: URL? = nil,
        autoCleanup: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        self.fileManager = fileManager
        self.autoCleanup = autoCleanup

        let base = baseDirectory ?? {
            let tmpPath = "/private/tmp"
            if fileManager.fileExists(atPath: tmpPath) {
                return URL(fileURLWithPath: tmpPath, isDirectory: true)
            } else {
                return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            }
        }()

        let uniqueDirName = "\(prefix)-\(UUID().uuidString)"
        self.rootURL = base.appendingPathComponent(uniqueDirName, isDirectory: true)

        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true, attributes: nil)
    }

    deinit {
        if autoCleanup {
            cleanup()
        }
    }

    /// 스코프 기반 동기 샌드박스 실행 헬퍼. 클로저 종료 시 자동으로 cleanup()이 호출됩니다.
    @discardableResult
    public static func withSandbox<T>(
        prefix: String = "swift-app-test",
        baseDirectory: URL? = nil,
        _ body: (TestSandbox) throws -> T
    ) throws -> T {
        let sandbox = try TestSandbox(prefix: prefix, baseDirectory: baseDirectory, autoCleanup: false)
        defer {
            sandbox.cleanup()
        }
        return try body(sandbox)
    }

    /// 스코프 기반 비동기 샌드박스 실행 헬퍼. 클로저 종료 시 자동으로 cleanup()이 호출됩니다.
    @discardableResult
    public static func withSandbox<T>(
        prefix: String = "swift-app-test",
        baseDirectory: URL? = nil,
        _ body: (TestSandbox) async throws -> T
    ) async throws -> T {
        let sandbox = try TestSandbox(prefix: prefix, baseDirectory: baseDirectory, autoCleanup: false)
        defer {
            sandbox.cleanup()
        }
        return try await body(sandbox)
    }

    /// 샌드박스 임시 디렉터리 및 하위 파일 전체를 삭제합니다.
    public func cleanup() {
        lock.lock()
        defer { lock.unlock() }

        guard !isCleanedUp else { return }
        if fileManager.fileExists(atPath: rootURL.path) {
            try? fileManager.removeItem(at: rootURL)
        }
        isCleanedUp = true
    }

    // MARK: - 경로 조회 헬퍼

    /// 샌드박스 루트 하위 상대 경로의 전체 URL을 반환합니다.
    public func url(for relativePath: String) -> URL {
        rootURL.appendingPathComponent(relativePath)
    }

    /// 샌드박스 루트 하위 상대 경로의 POSIX 경로 문자열을 반환합니다.
    public func path(for relativePath: String) -> String {
        url(for: relativePath).path
    }

    /// 해당 상대 경로에 파일이나 디렉터리가 존재하는지 확인합니다.
    public func exists(at relativePath: String) -> Bool {
        fileManager.fileExists(atPath: path(for: relativePath))
    }

    /// 해당 상대 경로에 파일이 존재하고 디렉터리가 아닌지 확인합니다.
    public func fileExists(at relativePath: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path(for: relativePath), isDirectory: &isDir)
        return exists && !isDir.boolValue
    }

    /// 해당 상대 경로에 디렉터리가 존재하는지 확인합니다.
    public func directoryExists(at relativePath: String) -> Bool {
        var isDir: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path(for: relativePath), isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    // MARK: - 파일 및 디렉터리 조작 헬퍼

    /// 샌드박스 내부에 디렉터리를 생성합니다 (중간 경로 포함).
    @discardableResult
    public func createDirectory(at relativePath: String) throws -> URL {
        let targetURL = url(for: relativePath)
        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
        return targetURL
    }

    /// 샌드박스 내부 상대 경로에 문자열 내용을 파일로 씁니다 (필요 시 상위 디렉터리 자동 생성).
    @discardableResult
    public func write(
        _ content: String,
        to relativePath: String,
        encoding: String.Encoding = .utf8
    ) throws -> URL {
        guard let data = content.data(using: encoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return try write(data, to: relativePath)
    }

    /// 샌드박스 내부 상대 경로에 바이너리 데이터를 파일로 씁니다 (필요 시 상위 디렉터리 자동 생성).
    @discardableResult
    public func write(
        _ data: Data,
        to relativePath: String
    ) throws -> URL {
        let targetURL = url(for: relativePath)
        let parentDir = targetURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }
        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }

    /// 샌드박스 내부 상대 경로의 파일 내용을 문자열로 읽습니다.
    public func readString(
        from relativePath: String,
        encoding: String.Encoding = .utf8
    ) throws -> String {
        let targetURL = url(for: relativePath)
        return try String(contentsOf: targetURL, encoding: encoding)
    }

    /// 샌드박스 내부 상대 경로의 파일 내용을 Data로 읽습니다.
    public func readData(from relativePath: String) throws -> Data {
        let targetURL = url(for: relativePath)
        return try Data(contentsOf: targetURL)
    }

    /// 샌드박스 내부 상대 경로의 파일이나 디렉터리를 삭제합니다.
    public func remove(at relativePath: String) throws {
        let targetURL = url(for: relativePath)
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
    }
}
