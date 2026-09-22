import XCTest
@testable import TestingAdapterKit

final class TestSandboxTests: XCTestCase {
    
    // MARK: - TestSandbox Tests

    func testSandboxCreationAndManualCleanup() throws {
        let sandbox = try TestSandbox(prefix: "test-creation", autoCleanup: false)
        let rootPath = sandbox.path

        XCTAssertTrue(FileManager.default.fileExists(atPath: rootPath), "생성 직후 디렉터리가 존재해야 합니다.")
        XCTAssertTrue(rootPath.contains("test-creation"), "접두사가 경로에 포함되어야 합니다.")

        sandbox.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootPath), "cleanup 후 디렉터리가 제거되어야 합니다.")
    }

    func testSandboxFileAndDirectoryOperations() throws {
        try TestSandbox.withSandbox(prefix: "test-ops") { sandbox in
            // 파일 쓰기 & 읽기
            let testText = "Hello TestSandbox!"
            let fileRelativePath = "nested/sample.txt"
            let fileURL = try sandbox.write(testText, to: fileRelativePath)

            XCTAssertEqual(fileURL.path, sandbox.path(for: fileRelativePath))
            XCTAssertTrue(sandbox.exists(at: fileRelativePath))
            XCTAssertTrue(sandbox.fileExists(at: fileRelativePath))
            XCTAssertFalse(sandbox.directoryExists(at: fileRelativePath))

            let readContent = try sandbox.readString(from: fileRelativePath)
            XCTAssertEqual(readContent, testText)

            // 바이너리 데이터 쓰기 & 읽기
            let sampleData = Data([0xDE, 0xAD, 0xBE, 0xEF])
            let binaryPath = "bin/data.bin"
            try sandbox.write(sampleData, to: binaryPath)
            let readData = try sandbox.readData(from: binaryPath)
            XCTAssertEqual(readData, sampleData)

            // 디렉터리 생성 및 판별
            let subDir = "custom/directory"
            try sandbox.createDirectory(at: subDir)
            XCTAssertTrue(sandbox.exists(at: subDir))
            XCTAssertTrue(sandbox.directoryExists(at: subDir))
            XCTAssertFalse(sandbox.fileExists(at: subDir))

            // 삭제 헬퍼
            try sandbox.remove(at: fileRelativePath)
            XCTAssertFalse(sandbox.exists(at: fileRelativePath))
        }
    }

    func testWithSandboxScopeAutoCleanup() throws {
        var sandboxRootPath: String = ""

        try TestSandbox.withSandbox(prefix: "test-scope") { sandbox in
            sandboxRootPath = sandbox.path
            XCTAssertTrue(FileManager.default.fileExists(atPath: sandboxRootPath), "스코프 내에서는 디렉터리가 존재해야 합니다.")
            try sandbox.write("test content", to: "data.txt")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: sandboxRootPath), "스코프 종료 후에는 자동으로 정리되어야 합니다.")
    }

    func testWithSandboxScopeCleanupOnThrow() {
        var sandboxRootPath: String = ""

        struct DummyError: Error {}

        XCTAssertThrowsError(
            try TestSandbox.withSandbox(prefix: "test-throw") { sandbox in
                sandboxRootPath = sandbox.path
                XCTAssertTrue(FileManager.default.fileExists(atPath: sandboxRootPath))
                throw DummyError()
            }
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: sandboxRootPath), "에러 발생 시에도 defer를 통해 자동 정리되어야 합니다.")
    }

    func testWithSandboxAsync() async throws {
        var sandboxRootPath: String = ""

        try await TestSandbox.withSandbox(prefix: "test-async") { sandbox in
            sandboxRootPath = sandbox.path
            XCTAssertTrue(FileManager.default.fileExists(atPath: sandboxRootPath))
            try sandbox.write("async content", to: "async.txt")
            let content = try sandbox.readString(from: "async.txt")
            XCTAssertEqual(content, "async content")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: sandboxRootPath), "비동기 스코프 종료 후 디렉터리가 삭제되어야 합니다.")
    }

    func testDeinitAutoCleanup() throws {
        var sandboxPath: String = ""

        do {
            let sandbox = try TestSandbox(prefix: "test-deinit", autoCleanup: true)
            sandboxPath = sandbox.path
            XCTAssertTrue(FileManager.default.fileExists(atPath: sandboxPath))
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: sandboxPath), "인스턴스 해제 시 deinit에서 디렉터리가 삭제되어야 합니다.")
    }

    // MARK: - TestEnvironment Tests

    func testWithTestEnvironmentVariableOverrideAndRestore() throws {
        let testKey = "TEST_ENV_KEY_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        
        // 1. 기존에 없던 변수 테스트
        XCTAssertNil(ProcessInfo.processInfo.environment[testKey])

        try TestEnvironment.withTestEnvironment([testKey: "TEMPORARY_VALUE"]) {
            XCTAssertEqual(ProcessInfo.processInfo.environment[testKey], "TEMPORARY_VALUE")
        }

        XCTAssertNil(ProcessInfo.processInfo.environment[testKey], "스코프 종료 후 unset 복원되어야 합니다.")

        // 2. 기존에 값이 있던 변수 덮어쓰기 및 복원
        setenv(testKey, "ORIGINAL_VALUE", 1)
        defer { unsetenv(testKey) }

        XCTAssertEqual(ProcessInfo.processInfo.environment[testKey], "ORIGINAL_VALUE")

        try TestEnvironment.withTestEnvironment([testKey: "MODIFIED_VALUE"]) {
            XCTAssertEqual(ProcessInfo.processInfo.environment[testKey], "MODIFIED_VALUE")
        }

        XCTAssertEqual(ProcessInfo.processInfo.environment[testKey], "ORIGINAL_VALUE", "스코프 종료 후 기존 값으로 복원되어야 합니다.")

        // 3. 기존 값이 있던 변수를 nil로 임시 unset
        try TestEnvironment.withTestEnvironment([testKey: nil]) {
            XCTAssertNil(ProcessInfo.processInfo.environment[testKey], "nil 전달 시 임시 unset 되어야 합니다.")
        }

        XCTAssertEqual(ProcessInfo.processInfo.environment[testKey], "ORIGINAL_VALUE", "스코프 종료 후 기존 값으로 복원되어야 합니다.")
    }

    func testWithEnvironmentVariableConvenience() throws {
        let testKey = "TEST_SINGLE_KEY_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"

        try TestEnvironment.withEnvironmentVariable(key: testKey, value: "SINGLE_VAL") {
            XCTAssertEqual(ProcessInfo.processInfo.environment[testKey], "SINGLE_VAL")
        }

        XCTAssertNil(ProcessInfo.processInfo.environment[testKey])
    }

    func testWithTestEnvironmentAsync() async throws {
        let testKey = "TEST_ASYNC_KEY_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"

        await TestEnvironment.withTestEnvironment([testKey: "ASYNC_VAL"]) {
            XCTAssertEqual(ProcessInfo.processInfo.environment[testKey], "ASYNC_VAL")
        }

        XCTAssertNil(ProcessInfo.processInfo.environment[testKey], "비동기 스코프 종료 후 복원되어야 합니다.")
    }
}
