#if canImport(Darwin)
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import StateRootKit

/// 손상된 mirror envelope를 mutation이 어떻게 다룰지 정한다.
public enum StateMirrorMutationRecovery: Sendable {
    /// 기존 동작: decode 오류를 호출자에게 전달하고 파일을 보존한다.
    case fail
    /// 손상된 envelope를 없는 상태로 보고 transform 결과로 명시적으로 교체한다.
    case replaceMalformed
}

/// 앱 상태 미러 — 모든 swift 앱이 자기 상태(모델 데이터)를 기계가 읽을 수 있게 게시한다.
///
/// 스크린샷 없이 CLI(`swift-app-router state <앱>`)로 앱 내부 데이터를 즉시 조회하기 위한
/// 공통 채널. 앱은 상태가 바뀔 때 `publish(...)` 한 줄이면 된다.
/// 파일: `~/.swift-app-state/<앱이름>.json` (덮어쓰기, updatedAt 포함 envelope).
public enum StateMirror {
    public static var dir: String {
        directory()
    }

    public static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> String {
        if let override = environment["SWIFT_APP_STATE_DIRECTORY"],
           !override.isEmpty {
            return (override as NSString).standardizingPath
        }
        // 테스트 프로세스는 **사용자의 실제 미러에 쓰지 않는다.**
        //
        // 오버라이드가 있어도 테스트가 그걸 설정하는 걸 잊으면 그대로 새어나간다 —
        // 2026-08-10 실측: ADM 테스트의 픽스처가 `~/.swift-app-state/AppBuildManager.json`
        // 에 게시돼(`root: /fixture/root-b` · `appCount: 1` · `sourceCheckError: cannot change
        // to '/fixture/root-b'`) 미러를 읽는 모든 소비자(GUI·에이전트·다른 앱)가 거짓값을
        // 받고 있었다. 잊을 수 있는 규율 대신 kit 이 막는다.
        if isRunningUnderTest(environment) {
            return (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("swift-app-state-tests")
        }
        // 홈을 직접 조립하지 않고 StateRootKit 해석을 상속한다 — router·소비자가
        // 테넌트 컨텍스트에서 StateRootKit 경로로 읽는데 게시가 홈에 쓰면 채널이
        // 갈라진다(2026-09-02 실측: 함대 전체 상태가 router 에서 "미게시").
        // resolve() 는 env 오버라이드·테스트 격리·테넌트 루트·홈 순서로 풀린다.
        return (StateRootKit.resolve(environment: environment, homeDirectory: homeDirectory)
            as NSString).appendingPathComponent(".swift-app-state")
    }

    /// XCTest/swift-testing 러너가 프로세스에 심는 표식. 테스트 코드가 자기를 신고할
    /// 필요 없이 러너 환경만 보고 판정한다.
    static func isRunningUnderTest(_ environment: [String: String]) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["SWIFT_TESTING_ENABLED"] != nil
    }

    /// `<앱이름>.json` 의 전체 경로. 게시·정리·소비자가 같은 규칙을 쓰도록 한 곳에 둔다.
    public static func path(app: String) -> String {
        (dir as NSString).appendingPathComponent("\(app).json")
    }

    // MARK: - Room-Scoped StateMirror SSOT

    /// 특정 앱의 고객용 단일 룸 격리 저장소 URL.
    /// `~/Library/Application Support/net.ranode.shared/rooms/<room-id>/<slug>/`
    public static func roomStorageURL(
        app: String,
        roomID: String = StateRootKit.defaultRoomID,
        homeDirectory: String? = nil
    ) -> URL {
        StateRootKit.customerAppStorageURL(slug: app, roomID: roomID, homeDirectory: homeDirectory)
    }

    /// 특정 앱의 고객용 단일 룸 격리 미러 파일 URL.
    /// `~/Library/Application Support/net.ranode.shared/rooms/<room-id>/<slug>/state.json`
    public static func roomMirrorURL(
        app: String,
        roomID: String = StateRootKit.defaultRoomID,
        homeDirectory: String? = nil
    ) -> URL {
        StateRootKit.customerStateMirrorURL(slug: app, roomID: roomID, homeDirectory: homeDirectory)
    }

    /// 룸 지정 또는 환경변수(ROOM_ID, CUSTOMER_ROOM_ID, SANDBOX_ROOM_ID)가 있을 때 룸 격리 미러 URL을 반환하고,
    /// 일반 환경일 때는 레거시 `.swift-app-state/<app>.json` URL을 반환한다.
    public static func resolveMirrorURL(
        app: String,
        roomID: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> URL {
        if let override = environment["SWIFT_APP_STATE_DIRECTORY"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).standardizingPath)
                .appendingPathComponent("\(app).json")
        }
        if isRunningUnderTest(environment) {
            return URL(fileURLWithPath: (NSTemporaryDirectory() as NSString)
                .appendingPathComponent("swift-app-state-tests"))
                .appendingPathComponent("\(app).json")
        }
        if let room = roomID ?? environment["ROOM_ID"] ?? environment["CUSTOMER_ROOM_ID"] ?? environment["SANDBOX_ROOM_ID"], !room.isEmpty {
            return roomMirrorURL(app: app, roomID: room, homeDirectory: homeDirectory)
        }
        return URL(fileURLWithPath: directory(environment: environment, homeDirectory: homeDirectory))
            .appendingPathComponent("\(app).json")
    }

    /// 특정 룸 스코프의 상태를 게시한다.
    public static func publishRoom<T: Encodable>(
        app: String,
        roomID: String = StateRootKit.defaultRoomID,
        _ state: T
    ) {
        let url = roomMirrorURL(app: app, roomID: roomID)
        try? withExclusiveLock(for: url) {
            try write(app: app, state: state, to: url)
        }
        StateMirrorSignal.post(app: app)
    }

    /// 특정 룸 스코프의 상태를 읽는다.
    public static func readRoom<State: Decodable & Sendable>(
        app: String,
        roomID: String = StateRootKit.defaultRoomID,
        as type: State.Type
    ) throws -> StateMirrorEnvelope<State> {
        try read(url: roomMirrorURL(app: app, roomID: roomID), as: type)
    }

    /// 특정 룸 스코프의 상태 미러를 정리한다.
    public static func clearRoom(
        app: String,
        roomID: String = StateRootKit.defaultRoomID
    ) {
        let url = roomMirrorURL(app: app, roomID: roomID)
        try? withExclusiveLock(for: url) {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        StateMirrorSignal.post(app: app)
    }

    /// 특정 룸 스코프의 자가 치유 저장소를 반환한다.
    public static func selfHealingStore<State: Codable & Sendable>(
        app: String,
        roomID: String = StateRootKit.defaultRoomID,
        homeDirectory: String? = nil
    ) -> StateMirrorSelfHealingStore<State> {
        StateMirrorSelfHealingStore<State>(
            app: app,
            roomID: roomID,
            homeDirectory: homeDirectory
        )
    }

    struct Envelope<S: Encodable>: Encodable {
        let app: String
        let updatedAt: String
        let state: S
    }

    /// Encodable 상태를 게시한다(envelope: app·updatedAt·state).
    public static func publish<T: Encodable>(app: String, _ state: T) {
        let url = URL(fileURLWithPath: path(app: app))
        try? withExclusiveLock(for: url) {
            try write(app: app, state: state, to: url)
        }
        StateMirrorSignal.post(app: app)
    }

    /// 현재 상태를 읽고 변환한 결과를 같은 interprocess lock 안에서 게시한다.
    ///
    /// 서로 다른 프로세스가 같은 앱 mirror 의 일부 필드만 갱신해야 할 때 read→write
    /// 사이에 다른 writer 의 terminal state가 끼어드는 lost update를 막는다.
    /// transform 안에서 같은 URL의 `publish`·`mutate`·`clear`를 다시 호출하면 안 된다.
    /// 이 lock은 의도적으로 재진입 가능하지 않다.
    @discardableResult
    public static func mutate<T: Codable & Sendable>(
        app: String,
        as type: T.Type,
        recovery: StateMirrorMutationRecovery = .fail,
        _ transform: (T?) throws -> T
    ) throws -> T {
        try mutate(
            url: URL(fileURLWithPath: path(app: app)),
            app: app,
            as: type,
            recovery: recovery,
            transform
        )
    }

    /// 테스트·격리 저장소용 URL 지정 overload.
    ///
    /// `.replaceMalformed`는 손상된 기존 파일을 transform 결과로 덮어쓰는 명시적
    /// 복구 정책이다. 기본값은 원본 보존을 위해 `.fail`이다.
    @discardableResult
    public static func mutate<T: Codable & Sendable>(
        url: URL,
        app: String,
        as type: T.Type,
        recovery: StateMirrorMutationRecovery = .fail,
        _ transform: (T?) throws -> T
    ) throws -> T {
        try withExclusiveLock(for: url) {
            let existing: T?
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    existing = try read(url: url, as: type).state
                } catch StateMirrorReadError.malformed
                    where recovery == .replaceMalformed {
                    existing = nil
                }
            } else {
                existing = nil
            }
            let updated = try transform(existing)
            try write(app: app, state: updated, to: url)
            StateMirrorSignal.post(app: app)
            return updated
        }
    }

    /// [String: Any] 류 임의 딕셔너리 게시(비-Codable 편의).
    public static func publishJSONObject(app: String, _ object: [String: Any]) {
        let url = URL(fileURLWithPath: path(app: app))
        try? withExclusiveLock(for: url) {
            try writeJSONObject(app: app, object: object, to: url)
        }
        StateMirrorSignal.post(app: app)
    }

    /// 임의 딕셔너리 상태의 read→transform→write를 같은 interprocess lock에서 수행한다.
    ///
    /// transform이 `nil`을 반환하면 파일을 만들거나 변경하지 않는다. Codable `mutate`와
    /// 마찬가지로 transform 안에서 같은 URL의 mirror API를 재호출하면 안 된다.
    ///
    /// **같은 앱 미러를 GUI 와 CLI 두 프로세스가 나눠 쓸 때의 overlay 갱신 원시체**다 —
    /// `publish`·`publishJSONObject`는 파일을 통째로 덮어쓰므로, 한쪽이 자기 키만
    /// 다시 게시하면 다른 쪽이 게시한 키가 지워진다(VPNWireGuard 도그푸딩: CLI 가 터널
    /// 목록을 게시하면 앱이 게시한 단절·핸드셰이크 축이 사라지고, 앱이 6초마다 다시
    /// 게시하면 CLI 의 `settings` 키가 사라졌다). 각 writer 는 이 함수로 **자기 키만
    /// 덮어쓰고** 다른 writer 의 키는 보존한다.
    @discardableResult
    public static func mutateJSONObject(
        app: String,
        recovery: StateMirrorMutationRecovery = .fail,
        _ transform: ([String: Any]?) throws -> [String: Any]?
    ) throws -> [String: Any]? {
        let url = URL(fileURLWithPath: path(app: app))
        return try withExclusiveLock(for: url) {
            let existing: [String: Any]?
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    guard let envelope = try JSONSerialization.jsonObject(with: data)
                        as? [String: Any],
                        let state = envelope["state"] as? [String: Any]
                    else {
                        throw StateMirrorReadError.malformed(url.path)
                    }
                    existing = state
                } catch {
                    if recovery == .replaceMalformed {
                        existing = nil
                    } else if let readError = error as? StateMirrorReadError {
                        throw readError
                    } else {
                        throw StateMirrorReadError.malformed(error.localizedDescription)
                    }
                }
            } else {
                existing = nil
            }
            guard let updated = try transform(existing) else { return nil }
            try writeJSONObject(app: app, object: updated, to: url)
            return updated
        }
    }

    /// 자기 키만 **overlay 로** 게시한다 — 미러에 있는 다른 writer 의 키는 보존한다.
    ///
    /// `publish`·`publishJSONObject` 는 파일을 통째로 교체한다. 같은 앱 미러를 GUI 와 CLI
    /// 두 프로세스가 나눠 쓰면 통째 교체는 서로의 키를 지운다. **overlay 정책은 이 API 가
    /// 강제한다** — caller 가 `mutateJSONObject` 로 merge 루프를 손으로 베끄면 다음 앱에서
    /// 같은 사고가 재연되므로, 베끼는 대신 이 메서드를 부른다.
    @discardableResult
    public static func publishOverlay(
        app: String,
        recovery: StateMirrorMutationRecovery = .fail,
        _ object: [String: Any]
    ) throws -> [String: Any]? {
        try mutateJSONObject(app: app, recovery: recovery) { existing in
            var merged = existing ?? [:]
            for (key, value) in object { merged[key] = value }
            return merged
        }
    }

    /// 미러를 치운다 — **앱이 종료할 때 부른다**(`applicationWillTerminate`).
    ///
    /// 게시만 있고 정리가 없으면, 앱이 끝난 뒤에도 마지막 상태가 파일로 남아 소비자가 그걸
    /// 현재 사실로 읽는다(MenuFold 도그푸딩: 앱을 껐는데 CLI 가 `fold=collapsed` 를 ok 로
    /// 보고 — 실제로는 메뉴바에 그 앱 아이템 자체가 없었다). 앱이 없으면 그 상태도 없는 게
    /// 사실이므로, 낡은 값을 남기느니 지운다.
    ///
    /// 파일 부재는 계약(`docs/app-interop-contract.md`)의 `health.freshness` 관점에서도
    /// "센서 죽음" 과 같은 뜻이라 소비자 해석이 어긋나지 않는다.
    ///
    /// 한계: `SIGKILL`(강제 종료·크래시)은 가로챌 수 없어 미러가 남는다 —
    /// 소비자는 프로세스 생존 확인을 백스톱으로 두어야 한다.
    ///
    /// 동시 waiter가 서로 다른 inode를 잠그는 일을 막기 위해 `.lock` sidecar는
    /// mirror를 지운 뒤에도 의도적으로 유지한다.
    public static func clear(app: String) {
        let url = URL(fileURLWithPath: path(app: app))
        try? withExclusiveLock(for: url) {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        StateMirrorSignal.post(app: app)
    }

    private static func write<T: Encodable>(
        app: String,
        state: T,
        to url: URL
    ) throws {
        let env = Envelope(
            app: app,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            state: state
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(env)
        try AtomicFileWriter().write(data, to: url)
    }

    private static func writeJSONObject(
        app: String,
        object: [String: Any],
        to url: URL
    ) throws {
        let envelope: [String: Any] = [
            "app": app,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
            "state": object,
        ]
        guard JSONSerialization.isValidJSONObject(envelope) else {
            throw StateMirrorReadError.malformed(
                "state contains a value that JSONSerialization cannot encode"
            )
        }
        let data = try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.prettyPrinted, .sortedKeys]
        )
        try AtomicFileWriter().write(data, to: url)
    }

    private static func withExclusiveLock<Result>(
        for mirrorURL: URL,
        _ operation: () throws -> Result
    ) throws -> Result {
        try FileManager.default.createDirectory(
            at: mirrorURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let lockPath = mirrorURL.path + ".lock"
        let descriptor = open(
            lockPath,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw posixError(operation: "open", path: lockPath)
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw posixError(operation: "flock", path: lockPath)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private static func posixError(operation: String, path: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [
                NSLocalizedDescriptionKey:
                    "\(operation) failed for \(path): \(String(cString: strerror(errno)))"
            ]
        )
    }
}
