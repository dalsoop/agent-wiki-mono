import Foundation

/// 사람이 실제로 친 입력만 남기는 필터.
///
/// P0 스파이크에서 드러난 실측 문제: 세 툴 모두 사용자 턴에 **시스템이 주입한 텍스트**를
/// 섞어 넣는다(`<system-reminder>`, 백그라운드 작업 완료 알림, goal 주입, `Caveat:` …).
/// 이걸 안 거르면 팩의 "사용자 지시" 절이 잡음으로 덮여 인수자가 목표를 오독한다.
/// 실제로 P0 1차 팩에서 16개 "사용자 지시" 중 3개가 시스템 주입물이었다.
///
/// swiftkit `SessionText.defaultNoise` 를 **확장**한다 — 그쪽은 claude 전용 3종이고,
/// 여기는 grok 의 배경작업 알림·goal 주입까지 본다.
public enum HumanText {
    static let rejectedPrefixes = [
        "<", "Caveat:", "[Request interrupted",
        // IDE 확장이 매 턴 붙이는 열린-탭 목록. 실측 codex 세션에서 사용자 지시 13개가
        // 전부 이 보일러플레이트였다 — 안 거르면 팩의 '최근 초점'이 통째로 무의미해진다.
        "# Context from my IDE setup",
        // 첨부 이미지의 크기 안내. 사람이 친 말이 아니다.
        "[Image:",
    ]
    static let rejectedContains = [
        "<system-reminder>",
        "<command-name>",
        "Background task \"",
        "This session is being continued from",
        // 하네스가 사용자 턴으로 밀어 넣는 훅 알림 — 실측에서 '최근 초점' 5개 중 3개가
        // 이것이었다(2026-07-27, 이 앱 자기 세션 도그푸딩).
        "Stop hook feedback",
        "Stop hook is now active",
    ]

    /// 사람 입력이면 다듬어서 반환, 아니면 nil.
    public static func clean(_ raw: String?) -> String? {
        guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        for p in rejectedPrefixes where t.hasPrefix(p) { return nil }
        for c in rejectedContains where t.contains(c) { return nil }
        return t
    }

    /// `SessionMeta.claude(head:clean:)` 에 넘기는 형태 — content 가 문자열이거나
    /// `[{type:"text"}]` 블록 배열일 수 있다.
    public static func cleanContent(_ content: Any?) -> String? {
        if let s = content as? String { return clean(s) }
        if let blocks = content as? [[String: Any]] {
            let joined = blocks
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
            return clean(joined)
        }
        return nil
    }

    /// 여러 줄을 한 줄로 눌러 길이 제한.
    public static func oneLine(_ s: String, cap: Int = 200) -> String {
        let j = s.split(whereSeparator: \.isNewline).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return j.count > cap ? String(j.prefix(cap)) + "…" : j
    }
}
