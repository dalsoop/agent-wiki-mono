import Foundation

/// **창에서 이 경로에 닿을 수 있나.**
///
/// macOS 는 `~/Documents`·`~/Desktop`·`~/Downloads` 를 보호한다. 서명·권한 없는 GUI 앱이
/// 그 아래를 열면 동의 대기로 `open()`/`stat()` 이 **영영 안 돌아온다.** 반면 터미널에서
/// 실행한 CLI 는 터미널의 권한을 물려받아 그냥 통과한다.
///
/// 그래서 같은 코드가 "CLI 는 0.05초 · 창은 무한" 으로 갈린다. 이건 버그처럼 안 보여서
/// 매번 처음부터 파게 된다 — 실측 2026-08-05 하루에 세 앱에서 같은 증상이 났다:
///
/// - `agent-profile-monitor` — `~/.claude/agents` 의 심볼릭 3개가 `~/Documents` 로 가서
///   창이 **무한 정지**(빈 창)
/// - `agent-skill-catalog` — `host-skills` 실체가 `~/Documents` 라 목록이 **조용히 0건**
/// - 스킬 경로 — `~/.codex/skills/<이름>` 처럼 **디렉터리가 심볼릭**이라 마지막 조각만
///   풀면 못 잡는다
///
/// 두 번 복붙한 판별을 여기로 올린다. 판단은 하나여야 한다.
public enum PrivacyReach: Sendable {
    /// 홈 아래에서 보호되는 최상위 디렉터리들.
    public static let protectedHomeDirectories = ["Documents", "Desktop", "Downloads"]

    /// 이 프로세스가 창을 띄우는 앱인가. CLI 는 터미널 권한을 물려받아 막히지 않는다.
    public static var isWindowedApp: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// 경로를 **조각마다** 풀어 실제 위치를 만든다.
    ///
    /// `URL.resolvingSymlinksInPath()` 로는 부족하다 — 대상이 아직 없는 심볼릭은 안 풀고,
    /// 그러면 디렉터리 심볼릭이 보호 경로로 이어지는 걸 놓친다(실측).
    public static func resolving(_ path: String, fileManager: FileManager = .default,
                                 depth: Int = 8) -> String {
        var current = ""
        for component in (path as NSString).pathComponents {
            current = current.isEmpty
                ? component
                : (current as NSString).appendingPathComponent(component)
            var hops = 0
            while hops < depth {
                let target: String
                do {
                    target = try fileManager.destinationOfSymbolicLink(atPath: current)
                } catch {
                    break
                }
                let next = target.hasPrefix("/")
                    ? target
                    : ((current as NSString).deletingLastPathComponent as NSString)
                        .appendingPathComponent(target)
                current = (next as NSString).standardizingPath
                hops += 1
            }
        }
        return current
    }

    /// 이 경로가 보호 구역에 있나(프로세스 종류와 무관한 사실).
    public static func isProtected(_ path: String, home: String = NSHomeDirectory(),
                                   fileManager: FileManager = .default) -> Bool {
        let resolved = resolving(path, fileManager: fileManager)
        let base = (home as NSString).standardizingPath
        guard resolved.hasPrefix(base + "/") else { return false }
        let tail = String(resolved.dropFirst(base.count + 1))
        let first = tail.split(separator: "/", maxSplits: 1).first.map(String.init) ?? tail
        return protectedHomeDirectories.contains(first)
    }

    /// **지금 이 프로세스가** 열면 막힐 수 있나.
    ///
    /// 열어보고 판단할 수 없다 — 여는 순간 돌아오지 않는다. 그래서 열기 **전에** 묻는다.
    public static func mayBlock(_ path: String, home: String = NSHomeDirectory(),
                                windowed: Bool = PrivacyReach.isWindowedApp,
                                fileManager: FileManager = .default) -> Bool {
        windowed && isProtected(path, home: home, fileManager: fileManager)
    }

    /// 사용자에게 보여줄 한 줄. **왜 안 보이는지**를 말해야 "없음" 으로 오해되지 않는다.
    public static func explanation(for path: String) -> String {
        "\((path as NSString).lastPathComponent) 는 보호 폴더(~/Documents 등) 아래라"
            + " 창에서 읽을 수 없다 — 터미널 CLI 로는 보인다"
    }
}
