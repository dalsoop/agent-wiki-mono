#if canImport(AppKit)
import Foundation

/// `Info.plist` 의 Sparkle feed 키를 읽는 작은 헬퍼.
///
/// `SUFeedURL` 은 `scripts/build-macos-app.sh` 가 공개 배포 빌드에서 박는다.
/// 개발 빌드엔 없고, 그때는 `SparkleUpdaterHost` 가 no-op 로 건너뛴다.
public enum FeedURL {
    /// 현재 번들의 `SUFeedURL`. 없으면 nil.
    public static var current: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }

    /// 공개키(SUPublicEDKey, Base64). appcast 서명 검증용.
    public static var publicEDKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    }
}

#endif
