import Foundation
import LocalizationKit

/// 임의의 `Swift.Error`를 정형화된 `AnyAppError`로 자동 변환하는 범용 에러 어댑터.
///
/// 시스템 에러(`CocoaError`, `POSIXError`), 비동기 취소(`CancellationError`),
/// 네트워크 에러(`URLError`), 레거시 Foundation 에러(`NSError`) 및 일반 사용자 정의 에러를
/// 규격화된 에러 코드, 카테고리, 심각도, 침묵(Silent) 여부로 매핑합니다.
/// `Task.isCancelled` 는 컨텍스트 키만 추가하며, silent 는 `CancellationError` 또는
/// category `.cancelled` 에만 적용합니다.
public enum UniversalErrorAdapter: Sendable {

    /// 임의의 `Swift.Error`를 분석하여 구조화된 `AnyAppError`로 변환합니다.
    ///
    /// - Parameters:
    ///   - error: 변환할 원본 에러.
    ///   - defaultCategory: 도메인을 판별할 수 없을 때 적용할 기본 카테고리 (기본값: `.unknown`).
    ///   - defaultSeverity: 심각도를 판별할 수 없을 때 적용할 기본 심각도 (기본값: `.error`).
    /// - Returns: 규격화된 `AnyAppError` 값 타입 인스턴스.
    public static func adapt(
        _ error: any Error,
        defaultCategory: ErrorCategory = .unknown,
        defaultSeverity: ErrorSeverity = .error
    ) -> AnyAppError {
        let taskCancelled = Task.isCancelled

        if let predefined = tryAdaptPredefined(error, taskCancelled: taskCancelled) {
            return predefined
        }

        return adaptFallback(
            error,
            defaultCategory: defaultCategory,
            defaultSeverity: defaultSeverity,
            taskCancelled: taskCancelled
        )
    }

    // MARK: - Internal Routing

    private static func tryAdaptPredefined(
        _ error: any Error,
        taskCancelled: Bool
    ) -> AnyAppError? {
        if let anyAppError = error as? AnyAppError {
            return resolveTaskCancellation(anyAppError, taskCancelled: taskCancelled)
        }
        if let appError = error as? any AppError {
            let converted = AnyAppError(appError)
            return resolveTaskCancellation(converted, taskCancelled: taskCancelled)
        }
        return nil
    }

    private static func adaptFallback(
        _ error: any Error,
        defaultCategory: ErrorCategory,
        defaultSeverity: ErrorSeverity,
        taskCancelled: Bool
    ) -> AnyAppError {
        switch error {
        case is CancellationError:
            return makeExplicitCancellationError()
        case let urlError as URLError:
            return UniversalURLErrorClassifier.classify(urlError, taskCancelled: taskCancelled)
        case let posixError as POSIXError:
            return UniversalPOSIXErrorClassifier.classify(posixError, taskCancelled: taskCancelled)
        case let cocoaError as CocoaError:
            return UniversalCocoaErrorClassifier.classify(cocoaError, taskCancelled: taskCancelled)
        default:
            return UniversalNSErrorClassifier.classify(
                error as NSError,
                originalError: error,
                defaultCategory: defaultCategory,
                defaultSeverity: defaultSeverity,
                taskCancelled: taskCancelled
            )
        }
    }

    private static func resolveTaskCancellation(
        _ error: AnyAppError,
        taskCancelled: Bool
    ) -> AnyAppError {
        guard taskCancelled else {
            return error
        }
        // Task.isCancelled 는 컨텍스트만 남긴다. 임의 실패를 silent 로 바꾸지 않는다.
        // silent 는 CancellationError 또는 category `.cancelled` 만.
        return error.withContext(key: "task_cancelled", value: "true")
    }

    private static func makeExplicitCancellationError() -> AnyAppError {
        AnyAppError(
            errorCode: "SYSTEM.TASK_CANCELLED",
            category: .cancelled,
            severity: .info,
            isSilent: true,
            context: ["cancellation_reason": "CancellationError"],
            underlyingErrorDescription: "Task was cancelled.",
            rawL10nKey: nil
        )
    }
}

// MARK: - Swift.Error Universal Extension

extension Swift.Error {
    /// 임의의 `Swift.Error`를 `UniversalErrorAdapter`를 통해 표준 `AnyAppError`로 변환합니다.
    public var asUniversalAppError: AnyAppError {
        UniversalErrorAdapter.adapt(self)
    }
}
