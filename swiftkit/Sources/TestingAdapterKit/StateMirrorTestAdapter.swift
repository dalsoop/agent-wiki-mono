import Foundation
import StateMirrorKit
import StateRootKit

/// StateMirror 대기 중 타임아웃 발생 시 던져지는 상세 진단 에러.
public struct StateMirrorWaitTimeoutError: Error, CustomStringConvertible, LocalizedError, Sendable {
    /// 관찰 중인 대상 슬러그 또는 앱 식별자
    public let slug: String
    /// 대상 미러 파일의 전체 경로
    public let fileURL: URL
    /// 최대 대기 시간 (초)
    public let timeout: TimeInterval
    /// 실제 경과 시간 (초)
    public let elapsed: TimeInterval
    /// 마지막으로 관찰된 상태 JSON 문자열 (있을 경우)
    public let lastObservedStateJSON: String?
    /// 마지막으로 발생한 디코딩/입출력 에러 (있을 경우)
    public let lastError: (any Error)?
    /// 조건 설명 또는 사용자 지정 메시지
    public let conditionDescription: String

    public init(
        slug: String,
        fileURL: URL,
        timeout: TimeInterval,
        elapsed: TimeInterval,
        lastObservedStateJSON: String? = nil,
        lastError: (any Error)? = nil,
        conditionDescription: String
    ) {
        self.slug = slug
        self.fileURL = fileURL
        self.timeout = timeout
        self.elapsed = elapsed
        self.lastObservedStateJSON = lastObservedStateJSON
        self.lastError = lastError
        self.conditionDescription = conditionDescription
    }

    public var description: String {
        var desc = "StateMirror for '\(slug)' at \(fileURL.path) did not satisfy '\(conditionDescription)' within \(String(format: "%.3f", timeout))s (elapsed: \(String(format: "%.3f", elapsed))s)."
        if let json = lastObservedStateJSON {
            desc += " Last observed state: \(json)"
        } else {
            desc += " File was missing or empty."
        }
        if let lastError = lastError {
            desc += " [last error: \(lastError)]"
        }
        return desc
    }

    public var errorDescription: String? {
        description
    }
}

/// StateMirror 파일의 갱신을 감시하고 원하는 상태로 수렴할 때까지 비동기 대기하는 테스트 어댑터.
///
/// `~/.swift-app-state/<slug>.json` 또는 격리된 `TestSandbox` 내부의 미러 파일을 추적하며,
/// `isBusy == false`, `state == "ready"` 등 다양한 상태 수렴 조건을 결정론적으로 단언합니다.
public final class StateMirrorTestAdapter: @unchecked Sendable {
    /// 관찰 대상 앱의 slug 식별자
    public let slug: String
    /// 대상 상태 미러 파일의 URL
    public let fileURL: URL
    /// 파일 시스템 매니저
    private let fileManager: FileManager

    // MARK: - Initializers

    /// 특정 앱의 slug 및 환경변수 설정을 바탕으로 어댑터를 초기화합니다.
    ///
    /// - Parameters:
    ///   - slug: 대상 앱 슬러그 (예: `"gujo"`, `"agent-fleet-map"`)
    ///   - environment: 환경변수 맵 (기본값: 현재 프로세스 환경)
    ///   - fileManager: 파일 관리자 (기본값: `.default`)
    public init(
        slug: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.slug = slug
        self.fileURL = StateMirror.resolveMirrorURL(app: slug, environment: environment)
        self.fileManager = fileManager
    }

    /// 명시적인 파일 URL을 지정하여 어댑터를 초기화합니다.
    ///
    /// - Parameters:
    ///   - fileURL: 미러 파일의 전체 URL
    ///   - slug: 선택적 슬러그 (기본값: 파일명의 확장자 제거 이름)
    ///   - fileManager: 파일 관리자 (기본값: `.default`)
    public init(
        fileURL: URL,
        slug: String? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.slug = slug ?? fileURL.deletingPathExtension().lastPathComponent
        self.fileManager = fileManager
    }

    /// `TestSandbox` 인스턴스 내부의 `.swift-app-state/<slug>.json`을 관찰하는 어댑터를 생성합니다.
    ///
    /// - Parameters:
    ///   - sandbox: 테스트 샌드박스 인스턴스
    ///   - slug: 대상 앱 슬러그
    ///   - inSubdirectory: `.swift-app-state` 하위 디렉터리 여부 (기본값: `true`)
    ///   - fileManager: 파일 관리자 (기본값: `.default`)
    public convenience init(
        sandbox: TestSandbox,
        slug: String,
        inSubdirectory: Bool = true,
        fileManager: FileManager = .default
    ) {
        let relativePath = inSubdirectory
            ? ".swift-app-state/\(slug).json"
            : "\(slug).json"
        let url = sandbox.url(for: relativePath)
        self.init(fileURL: url, slug: slug, fileManager: fileManager)
    }

    // MARK: - State Inspection

    /// 미러 파일이 현재 디스크에 존재하는지 여부.
    public var exists: Bool {
        fileManager.fileExists(atPath: fileURL.path)
    }

    /// 파일의 원시 바이트 데이터를 읽습니다.
    public func readData() throws -> Data {
        guard exists else {
            throw StateMirrorReadError.missing(fileURL.path)
        }
        return try Data(contentsOf: fileURL)
    }

    /// 상태 미러 파일의 최상위 Envelope 딕셔너리(`["app": ..., "updatedAt": ..., "state": ...]`)를 읽습니다.
    public func readRawEnvelope() throws -> [String: Any] {
        let data = try readData()
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StateMirrorReadError.malformed(fileURL.path)
        }
        return json
    }

    /// 상태 미러 파일의 내부 `state` 딕셔너리를 읽습니다.
    public func readRawState() throws -> [String: Any] {
        let envelope = try readRawEnvelope()
        guard let state = envelope["state"] as? [String: Any] else {
            throw StateMirrorReadError.malformed("state field is missing or not a JSON object")
        }
        return state
    }

    /// 상태 미러 파일의 내부 `state`를 지정된 `Decodable` 타입으로 디코딩하여 반환합니다.
    public func readState<T: Decodable & Sendable>(as type: T.Type = T.self) throws -> T {
        let envelope = try readEnvelope(as: type)
        return envelope.state
    }

    /// 상태 미러 파일의 전체 `StateMirrorEnvelope<T>`를 디코딩하여 반환합니다.
    public func readEnvelope<T: Decodable & Sendable>(as type: T.Type = T.self) throws -> StateMirrorEnvelope<T> {
        let data = try readData()
        do {
            return try JSONDecoder().decode(StateMirrorEnvelope<T>.self, from: data)
        } catch {
            throw StateMirrorReadError.malformed(error.localizedDescription)
        }
    }

    // MARK: - Async Waiting Helpers

    /// 미러 파일이 생성되고 `predicate`를 만족하는 `Decodable` 상태에 도달할 때까지 비동기 폴링하며 대기합니다.
    ///
    /// - Parameters:
    ///   - timeout: 최대 대기 시간(초). 기본값: `3.0`초
    ///   - pollInterval: 재시도 간격(초). 기본값: `0.05`초
    ///   - as: 디코딩할 상태 모델 타입
    ///   - description: 디버깅용 조건 설명 (선택)
    ///   - predicate: 상태 만족 여부를 판별하는 클로저
    /// - Returns: 조건을 만족한 최종 상태 모델 인스턴스
    @discardableResult
    public func waitUntilState<T: Decodable & Sendable>(
        timeout: TimeInterval = 3.0,
        pollInterval: TimeInterval = 0.05,
        as type: T.Type = T.self,
        description: String? = nil,
        predicate: @escaping @Sendable (T) throws -> Bool
    ) async throws -> T {
        let clock = ContinuousClock()
        let startTime = clock.now
        let timeoutNanos = Int64(max(0.001, timeout) * 1_000_000_000)
        let intervalNanos = UInt64(max(0.001, pollInterval) * 1_000_000_000)
        let deadline = startTime + .nanoseconds(timeoutNanos)

        let condDesc = description ?? "state conforming to \(type)"
        var lastCapturedStateJSON: String? = nil
        var lastCapturedError: (any Error)? = nil

        while clock.now < deadline {
            try Task.checkCancellation()

            if exists {
                do {
                    let envelope = try readEnvelope(as: type)
                    do {
                        let rawData = try readData()
                        if let rawStr = String(data: rawData, encoding: .utf8) {
                            lastCapturedStateJSON = rawStr
                        }
                    } catch {}
                    if try predicate(envelope.state) {
                        return envelope.state
                    }
                } catch {
                    lastCapturedError = error
                }
            }

            if clock.now >= deadline {
                break
            }
            try await Task.sleep(nanoseconds: intervalNanos)
        }

        // 데드라인 만료 후 마지막 1회 최종 확인
        try Task.checkCancellation()
        if exists {
            do {
                let envelope = try readEnvelope(as: type)
                do {
                    let rawData = try readData()
                    if let rawStr = String(data: rawData, encoding: .utf8) {
                        lastCapturedStateJSON = rawStr
                    }
                } catch {}
                if try predicate(envelope.state) {
                    return envelope.state
                }
            } catch {
                lastCapturedError = error
            }
        }

        let totalDuration = startTime.duration(to: clock.now)
        let elapsedSeconds = Double(totalDuration.components.seconds) +
            Double(totalDuration.components.attoseconds) / 1e18

        throw StateMirrorWaitTimeoutError(
            slug: slug,
            fileURL: fileURL,
            timeout: timeout,
            elapsed: elapsedSeconds,
            lastObservedStateJSON: lastCapturedStateJSON,
            lastError: lastCapturedError,
            conditionDescription: condDesc
        )
    }

    /// 미러 파일의 `state` 딕셔너리가 `predicate`를 만족할 때까지 비동기 폴링하며 대기합니다.
    ///
    /// - Parameters:
    ///   - timeout: 최대 대기 시간(초). 기본값: `3.0`초
    ///   - pollInterval: 재시도 간격(초). 기본값: `0.05`초
    ///   - description: 디버깅용 조건 설명 (선택)
    ///   - predicate: 딕셔너리 상태 만족 여부를 판별하는 클로저
    /// - Returns: 조건을 만족한 최종 `state` 딕셔너리
    @discardableResult
    public func waitUntilJSON(
        timeout: TimeInterval = 3.0,
        pollInterval: TimeInterval = 0.05,
        description: String? = nil,
        predicate: @escaping ([String: Any]) throws -> Bool
    ) async throws -> [String: Any] {
        let clock = ContinuousClock()
        let startTime = clock.now
        let timeoutNanos = Int64(max(0.001, timeout) * 1_000_000_000)
        let intervalNanos = UInt64(max(0.001, pollInterval) * 1_000_000_000)
        let deadline = startTime + .nanoseconds(timeoutNanos)

        let condDesc = description ?? "raw state dictionary condition"
        var lastCapturedStateJSON: String? = nil
        var lastCapturedError: (any Error)? = nil

        while clock.now < deadline {
            try Task.checkCancellation()

            if exists {
                do {
                    let state = try readRawState()
                    if let rawStr = TestingAdapterJSON.string(from: state) {
                        lastCapturedStateJSON = rawStr
                    }
                    if try predicate(state) {
                        return state
                    }
                } catch {
                    lastCapturedError = error
                }
            }

            if clock.now >= deadline {
                break
            }
            try await Task.sleep(nanoseconds: intervalNanos)
        }

        // 데드라인 만료 후 마지막 1회 최종 확인
        try Task.checkCancellation()
        if exists {
            do {
                let state = try readRawState()
                if let rawStr = TestingAdapterJSON.string(from: state) {
                    lastCapturedStateJSON = rawStr
                }
                if try predicate(state) {
                    return state
                }
            } catch {
                lastCapturedError = error
            }
        }

        let totalDuration = startTime.duration(to: clock.now)
        let elapsedSeconds = Double(totalDuration.components.seconds) +
            Double(totalDuration.components.attoseconds) / 1e18

        throw StateMirrorWaitTimeoutError(
            slug: slug,
            fileURL: fileURL,
            timeout: timeout,
            elapsed: elapsedSeconds,
            lastObservedStateJSON: lastCapturedStateJSON,
            lastError: lastCapturedError,
            conditionDescription: condDesc
        )
    }

    /// 상태의 특정 키(`key`) 값이 예상 값(`equals`)과 같아질 때까지 대기합니다.
    ///
    /// - Parameters:
    ///   - key: 상태 딕셔너리 내의 키 이름
    ///   - expected: 기대하는 값 (`AnyHashable` 또는 기본 타입)
    ///   - timeout: 최대 대기 시간(초)
    ///   - pollInterval: 폴링 주기(초)
    @discardableResult
    public func waitUntilValue<V: Equatable>(
        forKey key: String,
        equals expected: V,
        timeout: TimeInterval = 3.0,
        pollInterval: TimeInterval = 0.05
    ) async throws -> [String: Any] {
        try await waitUntilJSON(
            timeout: timeout,
            pollInterval: pollInterval,
            description: "state['\(key)'] == \(expected)"
        ) { state in
            guard let val = state[key] as? V else {
                return false
            }
            return val == expected
        }
    }

    /// 앱이 준비 완료(Ready) 상태가 될 때까지 대기합니다.
    ///
    /// 다음 중 하나라도 만족하면 준비 완료로 간주합니다:
    /// - `isBusy == false`
    /// - `state == "ready"`
    /// - `status == "ready"`
    @discardableResult
    public func waitUntilReady(
        timeout: TimeInterval = 3.0,
        pollInterval: TimeInterval = 0.05
    ) async throws -> [String: Any] {
        try await waitUntilJSON(
            timeout: timeout,
            pollInterval: pollInterval,
            description: "isBusy == false || state == 'ready' || status == 'ready'"
        ) { state in
            if let isBusy = state["isBusy"] as? Bool, !isBusy {
                return true
            }
            if let st = state["state"] as? String, st.lowercased() == "ready" {
                return true
            }
            if let st = state["status"] as? String, st.lowercased() == "ready" {
                return true
            }
            return false
        }
    }

    /// 미러 파일이 디스크에 생성될 때까지 대기합니다.
    public func waitUntilFileExists(
        timeout: TimeInterval = 3.0,
        pollInterval: TimeInterval = 0.05
    ) async throws {
        try await AsyncPollingMatcher.expectEventually(
            timeout: timeout,
            pollInterval: pollInterval,
            message: "StateMirror file existence at \(fileURL.path)"
        ) { [self] in
            self.exists
        }
    }

    /// 미러 파일이 디스크에서 삭제(정리)될 때까지 대기합니다.
    public func waitUntilRemoved(
        timeout: TimeInterval = 3.0,
        pollInterval: TimeInterval = 0.05
    ) async throws {
        try await AsyncPollingMatcher.expectEventually(
            timeout: timeout,
            pollInterval: pollInterval,
            message: "StateMirror file removal at \(fileURL.path)"
        ) { [self] in
            !self.exists
        }
    }

    // MARK: - Test Writing Utilities

    /// 테스트 목업 또는 시뮬레이션을 위해 미러 파일에 상태를 직접 작성합니다.
    public func writeState<T: Encodable>(_ state: T) throws {
        let parentDir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }

        let envelope: [String: Any] = [
            "app": slug,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stateData = try encoder.encode(state)
        do {
            let envData = try JSONSerialization.data(withJSONObject: envelope)
            guard var jsonEnv = try JSONSerialization.jsonObject(with: envData) as? [String: Any],
                  let stateObject = try JSONSerialization.jsonObject(with: stateData) as? Any else {
                throw StateMirrorReadError.malformed("Failed to serialize state for writing")
            }
            jsonEnv["state"] = stateObject

            let finalData = try JSONSerialization.data(withJSONObject: jsonEnv, options: [.prettyPrinted, .sortedKeys])
            try finalData.write(to: fileURL, options: .atomic)
            StateMirrorSignal.post(app: slug)
        } catch let err as StateMirrorReadError {
            throw err
        } catch {
            throw StateMirrorReadError.malformed("Failed to serialize state for writing: \(error.localizedDescription)")
        }
    }

    /// 테스트 목업 또는 시뮬레이션을 위해 원시 딕셔너리를 미러 파일에 작성합니다.
    public func writeRawState(_ stateDict: [String: Any]) throws {
        let parentDir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true, attributes: nil)
        }

        let envelope: [String: Any] = [
            "app": slug,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "state": stateDict,
        ]

        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
        StateMirrorSignal.post(app: slug)
    }

    /// 미러 파일을 디스크에서 삭제합니다.
    public func clear() {
        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
            StateMirrorSignal.post(app: slug)
        }
    }
}
