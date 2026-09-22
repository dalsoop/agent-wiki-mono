import Foundation

/// 메뉴바 상주 앱들의 공통 갱신 루프 소유자.
///
/// `*-bar-swift` 앱들은 모두 같은 모양의 두 Task 를 손으로 들고 있었다 —
/// (1) 일회성 새로고침(`refreshTask`)과 (2) 간격 폴링 타이머(`autoTimerTask`).
/// 이 컨트롤러가 그 두 Task 의 생명주기(취소·재시작)와, 각 새로고침 뒤의
/// StateMirror 게시 훅을 한곳에서 소유한다. 앱은 자기 `refresh()` 클로저와
/// 간격만 넘긴다(내용/뷰는 앱이 그대로 소유 — 순수 protocol/closure 주도).
///
/// 원본 루프(github/gitlab/kube/pipeline-bar 에서 동일)와 동작이 같다:
/// 간격만큼 자고 → 취소 아니면 refresh, 그리고 `start` 는 즉시 1회 refresh 를 먼저 친다.
@MainActor
public final class MenuBarRefreshController {
    private var refreshTask: Task<Void, Never>?
    private var autoTimerTask: Task<Void, Never>?
    private let refresh: () async -> Void
    private let afterRefresh: (() -> Void)?
    private let minInterval: TimeInterval

    /// - Parameters:
    ///   - minInterval: 폴링 간격 하한(초). 0 이면 하한 없음. (token-bar 의 10초 하한 대체)
    ///   - refresh: 한 번의 갱신. 재진입 가드는 호출자(모델)가 책임진다(원본과 동일).
    ///     retain cycle 을 피하려면 `[weak self]` 로 넘길 것.
    ///   - afterRefresh: 매 refresh 직후 실행(예: StateMirror 게시). @MainActor.
    public init(
        minInterval: TimeInterval = 0,
        refresh: @escaping () async -> Void,
        afterRefresh: (() -> Void)? = nil
    ) {
        self.minInterval = minInterval
        self.refresh = refresh
        self.afterRefresh = afterRefresh
    }

    private func runRefresh() async {
        await refresh()
        afterRefresh?()
    }

    /// 진행 중 새로고침을 취소하고 백그라운드로 한 번 새로 친다(중복 방지).
    public func triggerRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.runRefresh() }
    }

    /// 간격 폴링 타이머를 (재)시작한다. `interval <= 0` 이면 정지만 한다.
    public func restart(interval: TimeInterval) {
        autoTimerTask?.cancel()
        autoTimerTask = nil
        guard interval > 0 else { return }
        let effective = max(minInterval, interval)
        autoTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(effective * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.runRefresh()
            }
        }
    }

    /// 앱 시작 시: 타이머 시작 + 즉시 1회 새로고침.
    public func start(interval: TimeInterval) {
        restart(interval: interval)
        triggerRefresh()
    }

    /// 두 Task 모두 취소.
    public func stop() {
        autoTimerTask?.cancel()
        autoTimerTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    deinit {
        autoTimerTask?.cancel()
        refreshTask?.cancel()
    }
}
