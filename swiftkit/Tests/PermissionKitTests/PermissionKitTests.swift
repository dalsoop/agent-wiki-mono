import XCTest
@testable import PermissionKit
import PermissionDialogKit

typealias FolderAccess = PermissionKit.FolderAccess

final class PermissionKitTests: XCTestCase {
    // MARK: Automation denial detection (the reusable, non-TCC logic)

    func testAutomationDeniedFromStderr() {
        XCTAssertTrue(Automation.isDenied(stderr: "execution error: Not authorized to send Apple events to Terminal. (-1743)"))
        XCTAssertTrue(Automation.isDenied(stderr: "... -1743 ..."))
        XCTAssertTrue(Automation.isDenied(stderr: "NOT AUTHORIZED"))   // case-insensitive
    }

    func testAutomationNotDeniedForOtherErrors() {
        XCTAssertFalse(Automation.isDenied(stderr: ""))
        XCTAssertFalse(Automation.isDenied(stderr: "syntax error: Expected end of line but found identifier. (-2741)"))
        XCTAssertFalse(Automation.isDenied(stderr: "Terminal got an error: can't make ..."))
    }

    func testAutomationDeniedFromErrorNumber() {
        XCTAssertTrue(Automation.isDenied(automationErrorNumber: -1743))
        XCTAssertFalse(Automation.isDenied(automationErrorNumber: -128))   // user cancelled
        XCTAssertFalse(Automation.isDenied(automationErrorNumber: nil))
    }

    // MARK: Localized copy is bilingual and names the app + Settings path

    func testDeniedMessageKorean() {
        let msg = Automation.deniedMessage(appName: "Proxmox Operations Manager", language: .korean)
        XCTAssertTrue(msg.contains("Proxmox Operations Manager"))
        XCTAssertTrue(msg.contains("자동화"))
    }

    func testDeniedMessageEnglish() {
        let msg = Automation.deniedMessage(appName: "Proxmox Operations Manager", language: .english)
        XCTAssertTrue(msg.contains("Proxmox Operations Manager"))
        XCTAssertTrue(msg.contains("Automation"))
    }

    func testDeniedMessageDiffersByLanguage() {
        let ko = Automation.deniedMessage(appName: "X", language: .korean)
        let en = Automation.deniedMessage(appName: "X", language: .english)
        XCTAssertNotEqual(ko, en)
    }

    // MARK: FolderAccess (파일·폴더 TCC 게이트)

    func testFolderAccessReadableDir() {
        // 읽을 수 있는 임시 디렉터리는 접근 가능·미차단.
        let tmp = NSTemporaryDirectory()
        XCTAssertTrue(FolderAccess.canAccess(tmp))
        XCTAssertFalse(FolderAccess.isBlocked(anyOf: [tmp]))
    }

    func testFolderAccessNonexistentIsNotBlocked() {
        // 존재하지 않는 경로는 '접근 거부'로 단정하지 않는다(그냥 없음).
        let ghost = "/nonexistent-\(UUID().uuidString)"
        XCTAssertTrue(FolderAccess.canAccess(ghost))
        XCTAssertFalse(FolderAccess.isBlocked(anyOf: [ghost]))
    }

    func testFolderAccessSettingsAnchor() {
        XCTAssertTrue(FolderAccess.settingsURLString.contains("Privacy_FilesAndFolders"))
    }

    // MARK: Residual TCC + auto repair

    func testResidualListGuidanceMentionsAutoCleanup() {
        let tip = Permission.residualListGuidance(appName: "ScreenshotSwift", language: .korean)
        XCTAssertTrue(tip.contains("ScreenshotSwift"))
        XCTAssertTrue(tip.contains("지우고") || tip.contains("등록"))
    }

    func testTCCServiceCatalogMatchesTccutilAndDBKeys() {
        XCTAssertEqual(TCCService.screenRecording.tccutilName, "ScreenCapture")
        XCTAssertEqual(TCCService.screenRecording.tccDatabaseKey, "kTCCServiceScreenCapture")
        XCTAssertEqual(TCCService.accessibility.tccutilName, "Accessibility")
        XCTAssertEqual(TCCService.camera.tccutilName, "Camera")
        XCTAssertEqual(TCCService.fullDiskAccess.tccutilName, "SystemPolicyAllFiles")
        XCTAssertEqual(TCCService(tccKey: "kTCCServiceCamera"), .camera)
        XCTAssertTrue(TCCService.screenRecording.supportsLiveRepair)
        XCTAssertFalse(TCCService.fullDiskAccess.supportsLiveRepair)
    }

    func testTCCUtilResetArgumentsAndInjectedRunner() {
        XCTAssertEqual(
            TCCUtil.resetArguments(service: .screenRecording, bundleID: "net.ranode.x"),
            ["reset", "ScreenCapture", "net.ranode.x"]
        )
        final class Rec: TCCUtilRunning, @unchecked Sendable {
            var args: [String] = []
            func runTCCUtil(arguments: [String]) -> Int32 {
                args = arguments
                return 0
            }
        }
        let rec = Rec()
        XCTAssertTrue(TCCUtil.reset(service: .accessibility, bundleID: "net.y", runner: rec))
        XCTAssertEqual(rec.args, ["reset", "Accessibility", "net.y"])
    }

    func testPermissionMapsToTCCService() {
        XCTAssertEqual(Permission.screenRecording.tccService, .screenRecording)
        XCTAssertEqual(Permission.accessibility.tccService, .accessibility)
        XCTAssertEqual(Permission.camera.tccService, .camera)
        XCTAssertEqual(Permission.fullDiskAccess.tccService, .fullDiskAccess)
        XCTAssertEqual(TCCService.screenRecording.runtimePermission, .screenRecording)
        XCTAssertEqual(TCCService.fullDiskAccess.runtimePermission, .fullDiskAccess)
    }

    /// FDA 판정은 "사용자 TCC.db 를 읽을 수 있는가" 하나로 서 있다. 프로브가 다른 경로를
    /// 보게 되면 권한이 있어도 없다고 답한다 — home 을 주입해 그 경로를 실측한다.
    func testFullDiskAccessProbeReadsExactlyTheUserTCCDatabase() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("permission-kit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let tcc = home.appendingPathComponent("Library/Application Support/com.apple.TCC", isDirectory: true)
        try FileManager.default.createDirectory(at: tcc, withIntermediateDirectories: true)

        XCTAssertFalse(
            Permission.canReadUserTCCDatabase(home: home.path),
            "TCC.db 가 없는데 FDA 가 있다고 답하면 앱이 온보딩을 건너뛴다")

        let database = tcc.appendingPathComponent("TCC.db")
        try Data("sqlite".utf8).write(to: database)
        XCTAssertTrue(Permission.canReadUserTCCDatabase(home: home.path))

        // 이름이 조금이라도 다르면 못 읽어야 한다 — 디렉터리 존재만으로 참이 되면 안 된다.
        try FileManager.default.moveItem(at: database, to: tcc.appendingPathComponent("TCC.db.backup"))
        XCTAssertFalse(Permission.canReadUserTCCDatabase(home: home.path))
    }

    func testStartupProbeSkipsFullDiskAccess() {
        XCTAssertNil(Permission.fullDiskAccess.grantedIfSafeToProbe)
        XCTAssertNotNil(Permission.camera.grantedIfSafeToProbe)
        XCTAssertNotNil(Permission.screenRecording.grantedIfSafeToProbe)
    }

    func testRepairReportAlreadyGrantedShape() {
        let r = PermissionRepairReport(
            phase: .alreadyGranted,
            granted: true,
            resetAttempted: false,
            resetSucceeded: false,
            detail: "ok"
        )
        XCTAssertTrue(r.granted)
        XCTAssertEqual(r.phase, .alreadyGranted)
    }
}
