import XCTest
@testable import PermissionKit

final class PermissionBootstrapTests: XCTestCase {

    // MARK: - argv 파싱

    func testRequestedServiceParsesStandardArgument() {
        let args = ["/path/LectureTools", "--permission-bootstrap=inputMonitoring"]
        XCTAssertEqual(PermissionBootstrap.requestedService(from: args), "inputMonitoring")
    }

    func testRequestedServiceParsesAccessibilityAndScreenRecording() {
        XCTAssertEqual(
            PermissionBootstrap.requestedService(from: ["x", "--permission-bootstrap=accessibility"]),
            "accessibility"
        )
        XCTAssertEqual(
            PermissionBootstrap.requestedService(from: ["x", "--permission-bootstrap=screenRecording"]),
            "screenRecording"
        )
    }

    func testRequestedServiceNilWhenMissingOrEmpty() {
        XCTAssertNil(PermissionBootstrap.requestedService(from: ["/app"]))
        XCTAssertNil(PermissionBootstrap.requestedService(from: ["--permission-bootstrap="]))
        XCTAssertNil(PermissionBootstrap.requestedService(from: ["--permission-bootstrap=  "]))
    }

    func testRequestedServiceIgnoresUnrelatedFlags() {
        let args = ["app", "--foo", "bar", "--permission-bootstrap=accessibility", "--baz"]
        XCTAssertEqual(PermissionBootstrap.requestedService(from: args), "accessibility")
    }

    // MARK: - supportsRegistration 계약

    func testSupportsRegistrationOnlyImplementedServices() {
        XCTAssertTrue(PermissionBootstrap.supportsRegistration(service: "accessibility"))
        XCTAssertTrue(PermissionBootstrap.supportsRegistration(service: "screenRecording"))
        XCTAssertTrue(PermissionBootstrap.supportsRegistration(service: "inputMonitoring"))
        XCTAssertFalse(PermissionBootstrap.supportsRegistration(service: "fullDiskAccess"))
        XCTAssertFalse(PermissionBootstrap.supportsRegistration(service: "camera"))
        XCTAssertFalse(PermissionBootstrap.supportsRegistration(service: "postEvent"))
        XCTAssertFalse(PermissionBootstrap.supportsRegistration(service: "unknown"))
    }

    func testArgumentPrefixIsStableForManagerInterop() {
        // MPM launcher / CLI 가 이 접두사에 의존한다 — 바꾸면 등록 파이프 전체 붕괴.
        XCTAssertEqual(PermissionBootstrap.argumentPrefix, "--permission-bootstrap=")
    }

    func testInputMonitoringRegistrationIsSupportedAndCallable() {
        // 크래시 없이 호출 가능(목록 생성은 통합/실기기). MainActor.
        XCTAssertTrue(PermissionBootstrap.supportsRegistration(service: "inputMonitoring"))
    }

    // MARK: - PrivacySettingsOpener candidates

    func testPrivacySettingsURLCandidatesIncludeClassicAndModern() {
        let classic = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        let cands = PrivacySettingsOpener.urlCandidates(from: classic)
        XCTAssertEqual(cands.first, classic)
        XCTAssertTrue(cands.contains {
            $0.contains("com.apple.settings.PrivacySecurity.extension")
                && $0.contains("Privacy_ListenEvent")
        })
    }

    func testPrivacySettingsURLCandidatesFromModernBackToClassic() {
        let modern = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        let cands = PrivacySettingsOpener.urlCandidates(from: modern)
        XCTAssertTrue(cands.contains {
            $0.contains("com.apple.preference.security") && $0.contains("Privacy_Accessibility")
        })
    }
}
