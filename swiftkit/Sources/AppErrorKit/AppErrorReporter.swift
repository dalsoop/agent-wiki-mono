import Foundation
import LocalizationKit

/// 커스텀 에러 핸들러 클로저 타입.
///
/// 오류 인스턴스와 발생 위치(파일, 라인) 정보를 전달받아 로깅, 원격 전송, UI 알림 등을 처리할 수 있습니다.
/// Swift 6 Concurrency 환경에서 완벽한 `Sendable` 무결성을 보장합니다.
public typealias ErrorHandler = @Sendable (AnyAppError, StaticString, UInt) -> Void

/// 핸들러 등록 해제용 식별자 토큰.
public struct HandlerRegistrationToken: Hashable, Sendable {
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}

/// 애플리케이션 전역 오류 보고 및 구조화 로깅 엔진.
///
/// Point-Free의 `swift-issue-reporting` 철학을 완벽히 반영하여 다음을 보장합니다:
/// 1. **테스트 환경 (XCTest / Swift Testing)**:
///    - 테스트 실행 중 예기치 못한 `AppError`가 보고되면 자동으로 실패를 기록(`Issue.record` 또는 `XCTFail`)하여
///      숨겨진 버그나 누락된 오류 처리를 사전에 탐지합니다.
///    - `withExpectedError { ... }` 스코프 내에서는 의도된 오류를 안전하게 포획하여 테스트 실패를 유예하고 단언(assert)할 수 있습니다.
/// 2. **런타임 / 프로덕션 환경**:
///    - Apple Unified Logging (`os.Logger`)을 통해 심각도(`ErrorSeverity`)에 대응되는 정밀한 로그 레벨(`.info`, `.warning`, `.error`, `.fault`)로 출력합니다.
///    - OpenTelemetry (OTel) Semantic Conventions 호환 구조화 속성(`exception.type`, `app.error.id` 등)을 지원합니다.
/// 3. **@MainActor / Sendable 완벽 분리**:
///    - `AppErrorReporter`는 완전히 `nonisolated`이며 `Sendable` 구조체입니다.
///    - 백그라운드 태스크, 비동기 작업, CLI, GUI 어디서든 락 프리 / 스레드 세이프하게 호출할 수 있으며
///      MainActor를 차단하거나 강제하지 않습니다.
public struct AppErrorReporter: Sendable {

    // MARK: - Singleton & State

    /// 싱글톤 공유 인스턴스.
    public static let shared = AppErrorReporter()

    /// 내부 스레드 안전 상태 저장소.
    let storage: Storage

    // MARK: - Scoped Overrides (Point-Free Style)

    /// 현재 태스크 범위에 한정된 로컬 에러 핸들러.
    @TaskLocal
    public static var currentHandler: ErrorHandler? = nil

    /// 현재 태스크 범위가 기대된 오류(`withExpectedError`) 스코프 내부인지 여부.
    @TaskLocal
    public static var isExpected: Bool = false

    // MARK: - Notification

    /// 오류가 기록될 때 노티피케이션 센터로 브로드캐스트되는 알림 이름.
    /// UI 레이어(@MainActor)에서 비침습적으로 에러 토스트/다이얼로그를 바인딩할 때 활용됩니다.
    public static let didRecordErrorNotification = Notification.Name("AppErrorReporter.didRecordError")

    // MARK: - Configuration

    /// 리포터 동작 구성 옵션.
    public struct Configuration: Sendable {
        /// 테스트 환경(XCTest / Swift Testing)에서 예기치 못한 에러 보고 시 테스트 실패 자동 기록 여부. 기본값: `true`.
        public var recordTestFailures: Bool

        /// 런타임/프로덕션 환경에서 Apple Unified Logging(OSLog)으로 구조화 로그 출력 여부. 기본값: `true`.
        public var emitOSLog: Bool

        /// OSLog 서브시스템 식별자. 기본값: `"com.gujo.apperror"`.
        public var logSubsystem: String

        /// OSLog 기본 카테고리 프리픽스. 기본값: `"AppError"`.
        public var logCategory: String

        public init(
            recordTestFailures: Bool = true,
            emitOSLog: Bool = true,
            logSubsystem: String = "com.gujo.apperror",
            logCategory: String = "AppError"
        ) {
            self.recordTestFailures = recordTestFailures
            self.emitOSLog = emitOSLog
            self.logSubsystem = logSubsystem
            self.logCategory = logCategory
        }
    }

    /// 현재 구성 정보.
    public var configuration: Configuration {
        get { storage.configuration }
        nonmutating set { storage.updateConfiguration { $0 = newValue } }
    }

    // MARK: - Initializer

    public init(configuration: Configuration = Configuration()) {
        self.storage = Storage(configuration: configuration)
    }

    // MARK: - Public Reporting API

    /// 임의의 `AppError`를 보고합니다.
    public func report(_ error: any AppError, file: StaticString = #fileID, line: UInt = #line) {
        let anyError = (error as? AnyAppError) ?? AnyAppError(error)
        record(anyError, file: file, line: line)
    }

    /// `AnyAppError` 값 타입 오류를 기록하고 핸들러/테스트러너/로거로 디스패치합니다.
    public func record(_ error: AnyAppError, file: StaticString = #fileID, line: UInt = #line) {
        let config = dispatchHandlers(for: error, file: file, line: line)

        NotificationCenter.default.post(
            name: Self.didRecordErrorNotification,
            object: error,
            userInfo: [
                "file": "\(file)",
                "line": line
            ]
        )

        guard !Self.isExpected else { return }
        dispatchDiagnostic(for: error, file: file, line: line, config: config)
    }

    private func dispatchHandlers(
        for error: AnyAppError,
        file: StaticString,
        line: UInt
    ) -> Configuration {
        if let scopedHandler = Self.currentHandler {
            scopedHandler(error, file, line)
        }
        let (single, multiple, config) = storage.snapshotHandlers()
        if let single {
            single(error, file, line)
        }
        for handler in multiple {
            handler(error, file, line)
        }
        return config
    }

    private func dispatchDiagnostic(
        for error: AnyAppError,
        file: StaticString,
        line: UInt,
        config: Configuration
    ) {
        if Self.isTesting && config.recordTestFailures {
            recordTestFailure(for: error, file: file, line: line)
            return
        }
        if config.emitOSLog {
            logToOSLog(for: error, file: file, line: line, config: config)
        }
    }

    // MARK: - Static Convenience API

    /// 공유 인스턴스를 통해 `AppError`를 보고합니다.
    public static func report(_ error: any AppError, file: StaticString = #fileID, line: UInt = #line) {
        shared.report(error, file: file, line: line)
    }

    /// 공유 인스턴스를 통해 `AnyAppError`를 기록합니다.
    public static func record(_ error: AnyAppError, file: StaticString = #fileID, line: UInt = #line) {
        shared.record(error, file: file, line: line)
    }

    // MARK: - Handler Management

    /// 전역 커스텀 에러 핸들러를 등록합니다.
    @discardableResult
    public func registerHandler(_ handler: @escaping ErrorHandler) -> HandlerRegistrationToken {
        let id = storage.addHandler(handler)
        return HandlerRegistrationToken(id: id)
    }

    /// 등록된 커스텀 에러 핸들러를 등록 해제합니다.
    public func unregisterHandler(_ token: HandlerRegistrationToken) {
        storage.removeHandler(token.id)
    }

    /// UUID 기반 등록 해제 편의 구문.
    public func unregisterHandler(_ id: UUID) {
        storage.removeHandler(id)
    }

    /// 단일 주요 핸들러를 설정합니다 (기존 단일 핸들러 대체, nil 전달 시 제거).
    public func setHandler(_ handler: ErrorHandler?) {
        storage.setSingleHandler(handler)
    }

    /// 등록된 모든 커스텀 핸들러를 초기화합니다.
    public func clearHandlers() {
        storage.clearHandlers()
    }

    /// 설정을 포함하여 리포터 상태를 초기 기본값으로 리셋합니다.
    public func reset() {
        storage.reset()
    }

    // Static Forwarding for Handler Management
    @discardableResult
    public static func registerHandler(_ handler: @escaping ErrorHandler) -> HandlerRegistrationToken {
        shared.registerHandler(handler)
    }

    public static func unregisterHandler(_ token: HandlerRegistrationToken) {
        shared.unregisterHandler(token)
    }

    public static func unregisterHandler(_ id: UUID) {
        shared.unregisterHandler(id)
    }

    public static func setHandler(_ handler: ErrorHandler?) {
        shared.setHandler(handler)
    }

    public static func clearHandlers() {
        shared.clearHandlers()
    }

    public static func reset() {
        shared.reset()
    }
}

// MARK: - AppError Ergonomic Extension

extension AppError {
    /// `AppErrorReporter.shared`를 통해 이 오류를 즉시 보고합니다.
    public func report(file: StaticString = #fileID, line: UInt = #line) {
        AppErrorReporter.shared.report(self, file: file, line: line)
    }
}
