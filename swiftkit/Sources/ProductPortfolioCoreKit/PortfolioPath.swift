import Foundation

/// 포트폴리오 visual/screenshot 경로의 홈 포터블 변환·해석.
///
/// JSON 에는 `~/...` 형태로 저장하고, 디스크 접근 전에는 `expandingTilde` 로 풀어 쓴다.
public enum PortfolioPath: Sendable {
    /// `~/...` 를 절대 경로로 펼친다. 그 외 경로는 trim 만 한다.
    public static func expandingTilde(
        _ path: String,
        home: String = NSHomeDirectory()
    ) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" {
            return home
        }
        if trimmed.hasPrefix("~/") {
            let rest = trimmed.dropFirst(2)
            return home + "/" + rest
        }
        return trimmed
    }

    /// 홈 절대 경로 prefix 를 `~/...` 로 바꾼다. 홈 밖 경로는 그대로 둔다.
    public static func makingPortable(
        _ path: String,
        home: String = NSHomeDirectory()
    ) -> String {
        let expanded = expandingTilde(path, home: home)
        let homeRoot = home.hasSuffix("/") ? String(home.dropLast()) : home
        if expanded == homeRoot {
            return "~"
        }
        let prefix = homeRoot + "/"
        if expanded.hasPrefix(prefix) {
            return "~/" + expanded.dropFirst(prefix.count)
        }
        return expanded
    }

    /// 해석된 절대 경로가 디스크에 존재하는지 검사한다.
    public static func fileExists(
        _ path: String,
        home: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(atPath: expandingTilde(path, home: home))
    }
}
