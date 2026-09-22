import Foundation

// HTTP 직접 크롤링이 막히는(403/로그인벽/JS 전용) 호스트 목록.
// 이 호스트들은 WebFetch 대신 browserctl(AgentBrowser) 렌더링 폴백이 필요하다.
// online-opportunity-radar 의 것과 동일 — 한 곳에서 유지.
public enum BotBlockedHosts {
    public static let hosts: [String] = [
        "kaggle.com",        // 403 + JS 렌더링 전용
        "lablab.ai",         // 상세 페이지 403
        "leetcode.com",      // 로그인/봇 차단
        "hackerrank.com",
        "codeforces.com",
        "instagram.com",     // 로그인 벽
        "threads.net",
        "facebook.com",
        "x.com",
        "twitter.com",
    ]

    /// URL 이 봇-차단 호스트로 알려져 있으면 true.
    public static func isKnownBotWalled(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
