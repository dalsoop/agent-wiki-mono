#if canImport(AppKit)
import AppKit
import Sparkle
import AppWindowKit

/// Sparkle 2 업데이터의 프로세스-전역 단일 호스트.
///
/// `SPUStandardUpdaterController`는 앱 생명주기 동안 **한 번**만 만들어야 한다
/// (여러 번 만들면 여러 스케줄러가 뜬다). 이 싱글턴이 그 가드를 담당한다.
///
/// 시작 시점에 `Info.plist`의 `SUFeedURL`을 읽고, 없으면 조용히 no-op 로깅만 한다
/// (개발 빌드처럼 아직 feed 주입 전이면 업데이터를 켜지 않는다). 공개 배포 빌드는
/// `scripts/build-macos-app.sh`가 `SUFeedURL`/`SUPublicEDKey`를 Info.plist에 박는다.
@MainActor
public final class SparkleUpdaterHost {
    public static let shared = SparkleUpdaterHost()

    private var controller: SPUStandardUpdaterController?
    public private(set) var didStart = false

    /// 마지막 시작 시도 사유. `SUFeedURL` 누락 등 진단용.
    public private(set) var lastStartStatus: StartStatus = .notStarted

    public enum StartStatus: Equatable {
        case notStarted
        case missingFeedURL
        case started
    }

    private init() {}

    /// 노출된 Sparkle 업데이터. 시작 전이거나 feed URL 이 없으면 nil.
    public var updater: SPUUpdater? { controller?.updater }

    /// 업데이터를 시작한다. 이미 시작됐으면 no-op.
    /// `SUFeedURL` 이 아직 없으면 잠그지 않고, 나중에 다시 호출하면 재시도한다.
    public func start() {
        if lastStartStatus == .started { return }

        guard FeedURL.current != nil else {
            lastStartStatus = .missingFeedURL
            return
        }
        didStart = true
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        lastStartStatus = .started
    }

    /// "업데이트 확인" 메뉴 액션 등에서 즉시 다이얼로그를 띄운다.
    public func checkForUpdates() {
        guard let updater else { return }
        updater.checkForUpdates()
    }
}

#endif
