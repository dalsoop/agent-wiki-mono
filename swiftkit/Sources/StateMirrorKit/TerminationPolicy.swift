import Foundation

// 종료 시 미러 처리 — 앱이 한 줄만 등록하면 되도록 배선을 여기로 옮긴다.
//
// 왜 패키지화하나: 미러를 게시하는 앱 17개 중 **16개가 종료 훅을 안 붙였다**. 잊는 게
// 기본값이면 범인은 보일러플레이트다(delegate 메서드 + import + 호출). 등록 한 줄로 줄인다.
//
// 무엇은 패키지화 못 하나: **어떤 키가 라이브인가는 앱 고유 지식**이다. MenuFold 의 `fold` 는
// 미러 전체가 라이브라 지우는 게 맞지만, RecordTimelabs 의 `state`/`busy` 는 녹화 파일 목록
// 같은 **데이터와 섞여** 있어 지우면 데이터까지 날린다. 그래서 정책을 앱이 고른다.
//
// AppKit 을 import 하지 않는다: 이 키트는 Foundation 전용이고 pim-* 같은 **CLI 타겟도 링크**한다.
// AppKit 을 끌어들이면 그 CLI 들이 전부 따라 링크한다. 종료 알림은 이름이 문자열이라
// Foundation 만으로 관측할 수 있다(앱이 아니면 애초에 발생하지 않으므로 CLI 는 자연히 무시된다).

extension StateMirror {
    /// 앱이 종료할 때 미러를 어떻게 할지.
    public enum TerminationPolicy: Sendable {
        /// 미러 **전체가 라이브 상태**일 때 — 앱이 없으면 그 상태도 없다(MenuFold 의 `fold`).
        case clear
        /// **라이브 플래그만 사실대로 덮어쓴다** — 나머지 데이터는 그대로 둔다.
        ///
        /// 마지막으로 게시된 미러를 읽어 여기 준 키만 바꿔 다시 쓴다. 앱 상태를 다시 계산하지
        /// 않으므로 모델을 붙잡을 필요가 없다(대부분 모델은 `@MainActor` 라, 종료 시점에
        /// 그걸 읽으려 하면 앱마다 격리 우회 코드가 생긴다).
        ///
        /// 예: RecordTimelabs 는 `state`/`busy` 만 거짓이 되고 녹화 목록·설정은 계속 참이다.
        case patchFinal([String: Sendable])
    }

    /// 종료 시 정책을 등록한다. 앱 시작 시 **한 번** 부른다.
    ///
    /// ```swift
    /// StateMirror.onTerminate(app: "MenuFold", .clear)
    /// StateMirror.onTerminate(app: "RecordTimelabs", .patchFinal(["state": "idle", "busy": false]))
    /// ```
    ///
    /// 한계: `SIGKILL`·크래시는 어떤 훅도 가로챌 수 없어 미러가 남는다 — 소비자는 프로세스
    /// 생존 확인을 백스톱으로 둬야 한다(계약의 `health.freshness` 도 같은 목적).
    public static func onTerminate(app: String, _ policy: TerminationPolicy) {
        TerminationRegistry.shared.register(app: app, policy: policy)
    }

    /// 등록된 정책을 실제로 적용한다. 종료 알림이 부르지만, 테스트가 알림 없이 검증할 수 있게 공개한다.
    public static func applyTerminationPolicy(app: String, _ policy: TerminationPolicy) {
        switch policy {
        case .clear:
            clear(app: app)
        case .patchFinal(let overrides):
            // lock을 얻은 뒤 최신 게시본을 읽어 준 키만 덮어쓴다. 게시된 적이 없으면 무시.
            do {
                _ = try mutateJSONObject(app: app) { existing in
                    guard var state = existing else { return nil }
                    for (key, value) in overrides { state[key] = value }
                    return state
                }
            } catch {}
        }
    }
}

/// 등록된 정책을 들고 종료 알림 한 번만 구독한다.
///
/// `NSApplicationWillTerminateNotification` 은 AppKit 의 알림이지만 이름이 문자열이라
/// Foundation 만으로 구독할 수 있다. CLI 프로세스에는 NSApplication 이 없어 발생하지 않으므로
/// 등록해도 아무 일이 없다(= CLI 가 게시한 데이터 미러를 실수로 지우지 않는다).
final class TerminationRegistry: @unchecked Sendable {
    static let shared = TerminationRegistry()

    private let lock = NSLock()
    private var policies: [String: StateMirror.TerminationPolicy] = [:]
    private var observing = false

    func register(app: String, policy: StateMirror.TerminationPolicy) {
        lock.lock()
        policies[app] = policy
        let needsObserver = !observing
        observing = true
        lock.unlock()

        guard needsObserver else { return }
        NotificationCenter.default.addObserver(
            forName: Notification.Name("NSApplicationWillTerminateNotification"),
            object: nil,
            queue: nil                       // 종료 중이라 메인 큐에 다시 태우면 실행 못 할 수 있다 — 동기 실행.
        ) { [weak self] _ in
            self?.applyAll()
        }
    }

    private func applyAll() {
        lock.lock()
        let snapshot = policies
        lock.unlock()
        for (app, policy) in snapshot {
            StateMirror.applyTerminationPolicy(app: app, policy)
        }
    }
}
