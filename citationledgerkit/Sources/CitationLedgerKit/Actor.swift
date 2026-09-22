import Foundation

/// 에이전트/사람 **주체(actor) 신원의 단일 해석기** — 원장을 쓰는 두 앱(KBW·forge)이
/// 같은 신원을 공유하도록. 지금까지 actor 문자열이 forge `FORGE_ACTOR`·KBW `--as`·
/// authors.json 세 곳에 흩어져 "이 에이전트가 누구"가 하나로 서지 않았다.
///
/// 정본은 파일 하나: `~/.config/citation-ledger/actor` (한 줄, 예 `agent:claude@macbook`).
/// 이 값이 forge 의 기본 actor·KBW 의 기본 author 로 함께 쓰이고, authors.json 의 우변도
/// 같은 문자열을 참조한다. 앱별 명시 override(FORGE_ACTOR·`--as`)는 각 앱이 먼저 처리하고,
/// 없을 때 이 해석기의 공유 기본값으로 떨어진다.
public enum CitationActor {

    /// 해석 우선순위: ① env `CITATION_ACTOR` ② 신원 파일 ③ `<user>@<host>` 폴백.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        if let a = environment["CITATION_ACTOR"], !a.trimmingCharacters(in: .whitespaces).isEmpty {
            return a.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let file = home.appendingPathComponent(".config/citation-ledger/actor")
        if let raw = try? String(contentsOf: file, encoding: .utf8) {
            let line = raw.split(whereSeparator: \.isNewline).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !line.isEmpty { return line }
        }
        return fallback(environment: environment)
    }

    /// 신원 미설정 시 — `<user>@<host>`. host 는 첫 라벨만(FQDN 잘라냄).
    public static func fallback(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        let user = environment["USER"] ?? NSUserName()
        let host = ProcessInfo.processInfo.hostName.split(separator: ".").first.map(String.init) ?? "unknown"
        return "\(user)@\(host)"
    }
}
