import Foundation

/// Store Ops 경로·한도. 홈 절대경로와 매직 숫자를 여기만 둔다.
public enum StoreOpsPaths {
    public static let envSourceRoot = "SA_SOURCE_ROOT"
    public static let envMonoRoot = "SWIFT_APP_MONO_ROOT"
    public static let usrLocalBin = "/usr/local/bin"

    public static func usrLocalCLI(_ name: String) -> String {
        (URL(fileURLWithPath: usrLocalBin) as URL).appendingPathComponent(name).path
    }

    /// SDK 관례 경로 (사용자 워크트리 경로가 아님).
    public static var androidSDKAdb: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Android/sdk/platform-tools/adb",
            "\(home)/Android/Sdk/platform-tools/adb",
        ]
    }

    /// env → cwd 위로 `apps/`+`swiftkit/` 탐색. 사용자 홈을 박지 않는다.
    public static func resolveMonoRoot(
        env: [String: String] = ProcessInfo.processInfo.environment,
        cwd: String = FileManager.default.currentDirectoryPath
    ) -> String {
        if let e = env[envSourceRoot], !e.isEmpty { return e }
        if let e = env[envMonoRoot], !e.isEmpty { return e }
        return discoverMonoRoot(from: cwd) ?? cwd
    }

    public static func discoverMonoRoot(from start: String) -> String? {
        var url = URL(fileURLWithPath: start, isDirectory: true)
        let fm = FileManager.default
        for _ in 0..<16 {
            let apps = url.appendingPathComponent("apps", isDirectory: true)
            let kit = url.appendingPathComponent("swiftkit", isDirectory: true)
            var appsDir: ObjCBool = false
            var kitDir: ObjCBool = false
            if fm.fileExists(atPath: apps.path, isDirectory: &appsDir), appsDir.boolValue,
               fm.fileExists(atPath: kit.path, isDirectory: &kitDir), kitDir.boolValue
            {
                return url.path
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }
}

/// 폴링·프로브 한도.
public enum StoreOpsLimits {
    public static let hubReadyWindowMinutes = 30
    public static let adbCoachPollMilliseconds = 1_500
    public static let auditEventLimit = 40
    public static let catalogSimTimeout: TimeInterval = 180
    public static let processTimeout: TimeInterval = 30
}
