#if canImport(AppKit)
import AppKit

/// 같은 bundle id 의 두 번째 인스턴스가 뜨는 것을 막는 공통 가드.
///
/// lecture-tools 가 인라인으로 갖고 있던 패턴을 일반화했다. 전역 이벤트 탭·풀스크린
/// 오버레이·상주 리소스를 쓰는 앱은 2중 실행 시 서로 리소스를 다투므로, `main()`(또는
/// `applicationDidFinishLaunching` 이전)에서 먼저 호출해 중복이면 기존 창을 띄우고 종료한다.
public enum SingleInstanceGuard {
    /// 이미 같은 bundle id 의 다른 인스턴스가 실행 중이면 그것을 활성화하고 `true` 를 반환한다.
    /// 호출자는 `true` 면 `app.run()` 전에 `return`/`exit` 해 이 중복 프로세스를 끝내야 한다.
    ///
    /// - Parameter activateExisting: 기존 인스턴스를 앞으로 가져올지(기본 true).
    /// - Returns: 중복이라 종료해야 하면 true, 유일 인스턴스면 false.
    @MainActor
    public static func isDuplicate(activateExisting: Bool = true) -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        guard let existing = others.first else { return false }
        if activateExisting {
            existing.activate(options: [.activateAllWindows])
        }
        return true
    }
}
#endif
