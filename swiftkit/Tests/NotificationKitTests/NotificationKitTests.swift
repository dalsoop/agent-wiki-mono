import XCTest
@testable import NotificationKit

final class NotificationKitTests: XCTestCase {
    /// 번들 없는 테스트 컨텍스트에서 post/requestAuthorization 가 크래시하지 않고 안전히 무시.
    func testNoBundleIsSafe() async {
        AppNotification.post(title: "t", body: "b")           // no crash
        let ok = await AppNotification.requestAuthorization()  // no crash
        #if canImport(UserNotifications)
        // macOS: 번들 없는 컨텍스트 → center nil → false.
        XCTAssertFalse(ok)
        #else
        // Linux/Windows: 권한 게이트 없음 → 항상 true.
        XCTAssertTrue(ok)
        #endif
    }

    func testEmergencyNotification() {
        // 긴급/비상 알림 호출 시 크래시 없이 정상 발송 경로 수행
        AppNotification.post(
            title: "⚠️ 긴급 테스트",
            body: "테스트 비상 알림입니다.",
            level: .emergency,
            soundName: "Sosumi"
        )
        AppNotification.post(
            title: "⚠️ 위험 테스트",
            body: "테스트 크리티컬 알림입니다.",
            level: .critical,
            soundName: "Basso"
        )
        XCTAssertTrue(NotificationLevel.emergency.isEmergency)
        XCTAssertTrue(NotificationLevel.critical.isEmergency)
        XCTAssertFalse(NotificationLevel.normal.isEmergency)
    }
}
