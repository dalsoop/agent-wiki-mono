#if canImport(AppKit)
import XCTest
@testable import AppWindowKit

final class AppActivationTests: XCTestCase {
    func testResolveApplicationURLFindsSystemApp() {
        // macOS 기본 앱인 Safari 또는 Calculator 탐색 검증
        let safariURL = AppActivation.resolveApplicationURL(named: "Safari")
        let calcURL = AppActivation.resolveApplicationURL(named: "Calculator")
        XCTAssertTrue(safariURL != nil || calcURL != nil, "Safari 또는 Calculator의 앱 번들 URL이 정상 해석되어야 함")
    }

    func testResolveApplicationURLNonExistentReturnsNil() {
        let nonExistent = AppActivation.resolveApplicationURL(named: "NonExistentAppBundle_XYZ_12345")
        XCTAssertNil(nonExistent, "존재하지 않는 앱 이름은 nil을 반환해야 함")
    }

    func testActivateNonExistentThrowsAppNotFound() {
        XCTAssertThrowsError(try AppActivation.activate(appName: "NonExistentAppBundle_XYZ_12345")) { error in
            guard let activationError = error as? AppActivation.ActivationError else {
                XCTFail("AppActivation.ActivationError 타입이어야 함: \(error)")
                return
            }
            switch activationError {
            case .appNotFound(let name):
                XCTAssertEqual(name, "NonExistentAppBundle_XYZ_12345")
            case .noGUISession:
                XCTAssertEqual(activationError.localizedDescription, "GUI WindowServer session unavailable (headless or SSH session)")
            default:
                XCTFail("예상치 못한 에러: \(activationError)")
            }
        }
    }
}
#endif
