import Foundation

/// Laravel 워크스페이스를 보는 앱들의 `status` — **한 번 쓰고 넷이 부른다.**
///
/// `laravel-architecture-graph` 같은 앱들은 `<apps-dir>` 을 요구하는 한 방 분석기라
/// 함대가 물어볼 창구가 없었다(관측 계약 `InteropKit.ObservabilityContract`).
///
/// status 는 **분석을 돌리지 않는다.** 볼 대상이 있는지만 말한다 — 그게 이 앱들이
/// 못 하게 되는 이유의 거의 전부다(경로가 없거나, 거기 Laravel 앱이 없거나).
/// 분석까지 하면 status 가 수 초씩 걸려서, 함대 조회가 통째로 느려진다.
public enum LaravelWorkspaceStatus {
    /// 관례 경로. 없으면 **없다고 말한다** — 다른 데를 뒤져서 지어내지 않는다.
    public static func defaultAppsDir(home: String? = nil) -> String {
        let resolved: String
        if let home {
            resolved = home
        } else {
            #if os(macOS)
            resolved = FileManager.default.homeDirectoryForCurrentUser.path
            #else
            resolved = NSHomeDirectory()
            #endif
        }
        let canonical = "\(resolved)/Documents/WORK/apps/laravel-mono/main/apps"
        if FileManager.default.fileExists(atPath: canonical) {
            return canonical
        }
        return "\(resolved)/Documents/WORK/WORKSPACE/apps/laravel-mono/main/apps"
    }

    /// Laravel 앱은 `artisan` 을 가진 디렉터리다. 그 파일이 판별 기준이다.
    public static func laravelApps(in dir: String,
                                   fileManager fm: FileManager = .default) -> [String] {
        guard fm.fileExists(atPath: dir) else { return [] }
        do {
            return try fm.contentsOfDirectory(atPath: dir)
                .filter { fm.fileExists(atPath: "\(dir)/\($0)/artisan") }
                .sorted()
        } catch {
            return []
        }
    }

    public static func payload(appsDir: String? = nil,
                               fileManager fm: FileManager = .default) -> [String: Any] {
        let dir = appsDir ?? defaultAppsDir()
        let exists = fm.fileExists(atPath: dir)
        let apps = laravelApps(in: dir, fileManager: fm)
        return [
            "appsDir": dir,
            "appsDirExists": exists,
            "laravelApps": apps.count,
            "apps": apps,
        ]
    }

    /// 사람이 읽는 줄들. JSON 과 **같은 값**을 낸다.
    ///
    /// - Parameter hint: 대상이 있을 때 이어서 칠 명령 한 줄(앱마다 다르다).
    public static func lines(appsDir: String? = nil,
                             hint: String,
                             fileManager fm: FileManager = .default) -> [String] {
        let dir = appsDir ?? defaultAppsDir()
        guard fm.fileExists(atPath: dir) else {
            return ["apps 디렉터리 없음: \(dir)", "경로를 직접 주면 된다: \(hint)"]
        }
        let apps = laravelApps(in: dir, fileManager: fm)
        return [
            "apps: \(dir)",
            "Laravel 앱 \(apps.count)개" + (apps.isEmpty ? "  (artisan 을 가진 디렉터리 없음)" : ""),
            "분석: \(hint)",
        ]
    }
}
