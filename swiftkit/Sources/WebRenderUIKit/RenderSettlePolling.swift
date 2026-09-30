import Foundation
import WebKit

/// 로드가 끝난 뒤 페이지 스크립트가 그리기를 마칠 때까지 기다린다.
///
/// WebKit 은 "JS 가 다 그렸다"는 신호를 주지 않는다. 짧은 간격으로 재서 다음이 모두 맞으면
/// 끝난 것으로 본다(최대 `limit`): 문서가 `complete`, 웹뷰가 로딩 중이 아님, 본문이 비어 있지
/// 않음, 본문 크기가 두 번 연속 같음, 최소 대기 시간이 지남. 로드 직후 스크립트로 다시
/// 이동하거나 본문을 늦게 채우는 사이트가 빈 본문으로 끝나지 않게 한다(2026-09-25 semas.or.kr 실측).
enum RenderSettlePolling {
    static let stableRounds = 2
    static let probe = "document.readyState + '|' + (document.body ? document.body.innerHTML.length : 0)"

    struct Sample: Equatable {
        let complete: Bool
        let length: Int

        /// `"complete|1234"` 형식. 못 읽으면 nil.
        static func parse(_ raw: String) -> Sample? {
            let parts = raw.split(separator: "|")
            guard parts.count == 2, let length = Int(parts[1]) else { return nil }
            return Sample(complete: parts[0] == "complete", length: length)
        }
    }

    /// 이번 표본이 이전 표본과 같고 다 그려진 상태인가.
    static func isSettled(previous: Sample?, current: Sample?, loading: Bool) -> Bool {
        guard let previous, let current, !loading, current.complete, current.length > 0 else { return false }
        return previous == current
    }

    @MainActor
    static func wait(_ webView: WKWebView, limit: TimeInterval) async throws {
        guard limit > 0 else { return }
        let start = Date()
        let deadline = start.addingTimeInterval(limit)
        let earliest = start.addingTimeInterval(min(WebRenderTimingConfig.settleMinimumWait, limit))
        var previous: Sample?
        var stable = 0
        while Date() < deadline {
            try await Task.sleep(for: .seconds(WebRenderTimingConfig.settleProbeInterval))
            let current: Sample?
            switch await measure(webView) {
            case .success(let sample): current = sample
            // 이동 중이면 스크립트가 실패한다 — 아직 안 그려진 것으로 보고 다음 회차에 다시 잰다.
            case .failure: current = nil
            }
            stable = isSettled(previous: previous, current: current, loading: webView.isLoading) ? stable + 1 : 0
            previous = current
            if stable >= stableRounds, Date() >= earliest { return }
        }
    }

    /// 크기 조정 뒤 한 번 그려질 시간을 준다.
    static func pause(_ seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(for: .seconds(seconds))
    }

    /// 읽지 못한 값은 nil(안정 판정에 들지 않는다). 스크립트 실패는 호출자가 판정한다.
    @MainActor
    private static func measure(_ webView: WKWebView) async -> Result<Sample?, Error> {
        do {
            let value = try await webView.evaluateJavaScript(probe)
            return .success((value as? String).flatMap(Sample.parse))
        } catch {
            return .failure(error)
        }
    }
}
