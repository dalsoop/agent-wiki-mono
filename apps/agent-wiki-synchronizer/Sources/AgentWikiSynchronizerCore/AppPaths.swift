import Foundation
import StateRootKit
import AppPathsKit

/// 프로세스·경로 상수. 새 명령을 박지 말고 여기에 모은다.
public enum AppPaths: Sendable {
    public static let uname = "/usr/bin/uname"
    public static let open = "/usr/bin/open"
    public static let slug = "agent-wiki-global"

    /// 설정·작업 sqlite. UserDefaults·StateMirror 가 아니다.
    public static var sqliteFile: URL { sqliteFile() }

    public static func sqliteFile(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        stateDirectory(environment: environment).appendingPathComponent("app.sqlite3")
    }


    /// 앱 상태 디렉터리 — env 오버라이드면 해당 경로, 일반 고객 환경이면 기기 로컬 룸 저장소.
    public static func stateDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[StateRootKit.declaredEnv], !override.isEmpty {
            return StateRootKit.url(".\(slug)", environment: environment)
        }
        return StateRootKit.ensureCustomerRoomStorage(slug: slug)
    }

    public static func stateFile(
        _ name: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        stateDirectory(environment: environment).appendingPathComponent(name, isDirectory: false)
    }
}
