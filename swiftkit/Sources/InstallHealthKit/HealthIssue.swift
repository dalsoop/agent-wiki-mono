import Foundation

/// 설치·자동시작 건강 문제 한 건.
public struct HealthIssue: Equatable, Sendable {
    public enum Severity: String, Sendable, CaseIterable {
        /// 지금 기능이 깨져 있다(중복 실행·확장 누락·자동시작 죽음).
        case error
        /// 아직 안 깨졌지만 재발 공장(정본 불일치·구 번들 잔재).
        case warning
    }

    public enum Kind: String, Sendable, CaseIterable {
        /// LaunchAgent 가 번들 실행 파일을 직접 exec — LaunchServices 중복 방지를 우회한다.
        case launchAgentDirectExec
        /// LaunchAgent 가 없는 경로를 가리킨다 — 자동시작이 조용히 죽는다.
        case launchAgentDangling
        /// 같은 bundle id 의 .app 이 둘 이상(구·신 이름 공존).
        case duplicateBundleID
        /// 같은 앱 프로세스가 둘 이상 떠 있다.
        case duplicateInstance
        /// 확장(.appex)·권한 Helper 를 심어야 하는 앱인데 설치본에 없다.
        case missingExtension
        /// 앱별 install-app.sh 가 이름·경로를 하드코딩해 Info.plist(정본)와 어긋난다.
        case installScriptDivergence
        /// 확장을 심는 앱인데 install-app.sh 가 공용 위임 shim 이다 — 확장이 조용히 빠진다.
        case shimDropsExtension
        /// 설치 앱을 실행하자마자 치명 크래시(리소스 번들·프레임워크 누락). .app 이 실제로 안 켜진다.
        case fatalLaunchCrash
        /// cutoff deny-list 앱이 실행 중이다 — 꺼야 한다.
        case denyListRunning
        /// SUFeedURL 이 있는데 Sparkle.framework 가 번들에 없다 — 고아 피드 URL.
        case sparkleFeedWithoutFramework
        /// PATH CLI(`/opt/homebrew/bin/<cli>`)가 심링크가 아니거나 dangling 이다.
        case cliSymlinkCheck
        /// PATH CLI 바이너리가 Sparkle 을 링크한다 — 업데이트는 GUI 가 담당한다.
        case cliSparkleRpath
    }

    public let kind: Kind
    public let severity: Severity
    /// 대상 식별자(plist 이름·bundle id·앱 디렉터리 등).
    public let subject: String
    /// 사람이 읽는 한 줄 설명.
    public let detail: String
    /// 고치는 방법(사람이 읽는 한 줄). 자동 수리 가능 여부는 `isAutoFixable`.
    public let remedy: String
    /// 앱/CLI 가 `--fix` 로 자동 수리할 수 있는가.
    public let isAutoFixable: Bool

    public init(
        kind: Kind,
        severity: Severity,
        subject: String,
        detail: String,
        remedy: String,
        isAutoFixable: Bool = false
    ) {
        self.kind = kind
        self.severity = severity
        self.subject = subject
        self.detail = detail
        self.remedy = remedy
        self.isAutoFixable = isAutoFixable
    }
}
