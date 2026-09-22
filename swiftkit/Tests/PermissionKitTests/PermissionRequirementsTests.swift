import Foundation
import XCTest
@testable import PermissionKit

/// 권한 요청 **정규화** 계약.
///
/// 배경(실측 2026-08-07~08): 온보딩은 요청 목록을 코드에 하드코딩, doctor 는 TCC 원장에
/// 이미 등록된 것만 조회, 상태 CLI 는 또 다른 목록 — 셋이 어긋나 "요청하는데 진단은 모르는"
/// 권한과 "죽었다는데 앱은 안 쓰는" 권한이 동시에 생겼다. 선언을 한 곳(Info.plist)에 두고
/// 세 소비자가 같은 파서를 쓰게 한 계약을 여기서 고정한다.
final class PermissionRequirementsTests: XCTestCase {

    // MARK: - 이름 왕복

    /// 선언 이름은 `TCCService` rawValue 와 같은 표기여야 한다 — 두 축이 다른 문자열을 쓰면
    /// 선언과 원장을 사람이 눈으로 맞춰야 한다.
    func testDeclaredNameRoundTripsForEveryRequestablePermission() {
        for permission in Permission.allCases {
            let name = permission.declaredName
            XCTAssertEqual(Permission(declaredName: name), permission, "왕복 실패: \(name)")
            XCTAssertEqual(TCCService(rawValue: name), permission.tccService)
        }
    }

    /// 원장에서 복붙한 TCC 키(`kTCCService…`)와 CLI 관행 kebab-case 도 받는다.
    func testAcceptsTCCDatabaseKeyAndKebabCase() {
        XCTAssertEqual(Permission(declaredName: "kTCCServiceScreenCapture"), .screenRecording)
        XCTAssertEqual(Permission(declaredName: "screen-recording"), .screenRecording)
        XCTAssertEqual(Permission(declaredName: "input-monitoring"), .inputMonitoring)
        XCTAssertEqual(Permission(declaredName: "location"), .location)
        XCTAssertEqual(Permission(declaredName: "kTCCServiceLocation"), .location)
        XCTAssertEqual(Permission(declaredName: "  accessibility  "), .accessibility)
    }

    func testRejectsUnknownNames() {
        XCTAssertNil(Permission(declaredName: "screenrecording"))
        XCTAssertNil(Permission(declaredName: ""))
        XCTAssertNil(Permission(declaredName: "sudo"))
    }

    /// 요청 가능한 서비스는 전부 `Permission` 에 있어야 한다 — 빠지면 그 권한은 앱이
    /// 원시 API 로 직접 요청하게 되고, 그게 정규화가 깨지는 지점이다.
    func testEveryRequestableTCCServiceHasARuntimePermission() {
        // 파일·개인정보 계열은 프롬프트 API 가 없어 런타임 게이트를 만들 수 없다(설정에서만).
        let noRuntimePrompt: Set<TCCService> = [
            .automation, .contacts, .calendars, .reminders, .photos, .postEvent,
            .desktopFolder, .documentsFolder, .downloadsFolder,
        ]
        let requestable = TCCService.allCases.filter { !noRuntimePrompt.contains($0) }
        let mapped = requestable.compactMap(\.runtimePermission)
        XCTAssertEqual(
            mapped.count, requestable.count,
            "런타임 Permission 이 없는 서비스: "
                + requestable.filter { $0.runtimePermission == nil }.map(\.rawValue).joined(separator: ", "))
        // 둘 이상이 같은 Permission 을 가리키면 한쪽 게이트가 다른 쪽 승인으로 열린다.
        XCTAssertEqual(Set(mapped).count, mapped.count, "서비스마다 Permission 이 유일해야 한다")
    }

    // MARK: - plist 파싱

    func testParsesRequiredAndOptional() {
        let d = PermissionRequirements.parse(
            required: ["screenRecording", "accessibility"],
            optional: ["camera"])
        XCTAssertEqual(d.required, [.screenRecording, .accessibility])
        XCTAssertEqual(d.optional, [.camera])
        XCTAssertEqual(d.all, [.screenRecording, .accessibility, .camera], "필수가 먼저 순회돼야 한다")
        XCTAssertFalse(d.isEmpty)
    }

    /// 오타를 조용히 버리면 "선언했는데 요청 안 되는" 권한이 생긴다 — 밖으로 보고한다.
    func testUnknownNamesAreReportedNotDropped() {
        let d = PermissionRequirements.parse(required: ["screenRecording", "screne-recording"],
                                             optional: nil)
        XCTAssertEqual(d.required, [.screenRecording])
        XCTAssertEqual(d.unknown, ["screne-recording"])
    }

    func testDuplicateDeclarationsCollapse() {
        let d = PermissionRequirements.parse(
            required: ["accessibility", "accessibility", "kTCCServiceAccessibility"],
            optional: nil)
        XCTAssertEqual(d.required, [.accessibility], "중복은 온보딩에서 같은 프롬프트를 두 번 띄운다")
    }

    /// 같은 권한을 필수·선택에 다 적었으면 필수가 이긴다 — 아니면 진행 게이트가 느슨해진다.
    func testRequiredWinsOverOptional() {
        let d = PermissionRequirements.parse(required: ["camera"], optional: ["camera", "microphone"])
        XCTAssertEqual(d.required, [.camera])
        XCTAssertEqual(d.optional, [.microphone])
    }

    func testMissingKeysGiveEmptyDeclaration() {
        let d = PermissionRequirements.parse(required: nil, optional: nil)
        XCTAssertTrue(d.isEmpty)
        XCTAssertTrue(d.unknown.isEmpty)
    }

    /// plist 값이 배열이 아닐 때(문자열 하나로 적는 실수) 크래시하지 않는다.
    func testNonArrayValueIsIgnoredSafely() {
        let d = PermissionRequirements.parse(required: "screenRecording", optional: 42)
        XCTAssertTrue(d.isEmpty)
    }

    // MARK: - 실제 plist 파일 읽기

    func testReadsDeclarationFromInfoPlistFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("perm-req-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("Info.plist")
        let plist: [String: Any] = [
            "CFBundleIdentifier": "net.ranode.example",
            PermissionRequirements.requiredKey: ["screenRecording"],
            PermissionRequirements.optionalKey: ["microphone"],
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: path)

        let d = try XCTUnwrap(PermissionRequirements.declared(infoPlistPath: path.path))
        XCTAssertEqual(d.required, [.screenRecording])
        XCTAssertEqual(d.optional, [.microphone])
    }

    func testMissingFileReturnsNilNotEmptyDeclaration() {
        // nil 과 "빈 선언" 은 다르다 — 전자는 못 읽음, 후자는 요구 없음. 진단이 이걸 구분해야 한다.
        XCTAssertNil(PermissionRequirements.declared(infoPlistPath: "/nope/Info.plist"))
    }

    // MARK: - AV 계열 판정

    /// 카메라·마이크만 비동기 승인(`requestAccess`)을 await 해야 한다.
    func testOnlyAVPermissionsExposeAMediaType() {
        XCTAssertEqual(Permission.camera.avMediaType, .video)
        XCTAssertEqual(Permission.microphone.avMediaType, .audio)
        for permission: Permission in [.screenRecording, .accessibility, .inputMonitoring, .fullDiskAccess] {
            XCTAssertNil(permission.avMediaType, "\(permission) 는 동기 preflight 경로다")
        }
    }
}

/// UI 없는 경로용 조용한 게이트 계약.
///
/// 실측 2026-08-08: voice-scribe CaptureEngine 이 원시 `AVCaptureDevice` 스위치를
/// `ensureGranted` 로 치환하면서 "거부 시 조용히 false" 가 **모달 경고**로 바뀌었다.
/// 캡처 엔진·CLI·백그라운드는 사람이 없어서 모달이 뜨면 호출이 그대로 멈춘다.
final class QuietGateContractTests: XCTestCase {

    /// 기본값은 기존 동작(경고 표시)이어야 한다 — 바꾸면 이미 쓰는 GUI 앱들이 조용해진다.
    func testAlertIsShownByDefault() throws {
        let signature = "presentAlertOnDenial: Bool = true"
        let source = try sourceText("Permission.swift")
        XCTAssertTrue(source.contains(signature),
                      "기본값 true 를 유지해야 GUI 호출부 동작이 안 바뀐다")
    }

    /// UI 없는 경로가 실제로 조용한 경로를 쓰고 있는지 — 계약이 문서에만 있으면 지켜지지 않는다.
    ///
    /// 이 파일은 swiftkit 패키지 **밖**(apps/voice-scribe-swift)에 있다. sparse-checkout
    /// 워크트리에는 그 앱이 없어서 예전에는 "파일 없음" 으로 빨간불이 났다 — 환경 차이지
    /// 계약 위반이 아니다. 없으면 건너뛰고, 있으면 그대로 잰다.
    func testCaptureEnginePathOptsOutOfTheAlert() throws {
        let relative = "../../../apps/voice-scribe-swift/Sources/VoiceScribe/CaptureEngine.swift"
        guard let source = sourceTextIfPresent(relative) else {
            throw XCTSkip("voice-scribe 가 이 워크트리에 체크아웃돼 있지 않다(sparse) — 계약 판정 불가")
        }
        XCTAssertTrue(source.contains("presentAlertOnDenial: false"),
                      "UI 없는 캡처 경로는 모달을 띄우면 멈춘다")
    }

    /// 프롬프트 직후 재판정이 있어야 한다 — 없으면 방금 허용한 사용자를 거부로 보고한다.
    func testRechecksAfterPromptBeforeReportingDenial() throws {
        let source = try sourceText("Permission.swift")
        guard let range = source.range(of: "if presentAlertOnDenial {") else {
            return XCTFail("조용한 분기를 못 찾음")
        }
        let before = String(source[source.startIndex..<range.lowerBound])
        XCTAssertTrue(before.hasSuffix("if isGranted { return true }\n        ")
                      || before.contains("if isGranted { return true }\n        if presentAlertOnDenial"),
                      "경고 직전에 isGranted 재확인이 있어야 한다")
    }

    private func sourceTextIfPresent(_ relative: String) -> String? {
        try? sourceText(relative)
    }

    private func sourceText(_ relative: String) throws -> String {
        // Tests/PermissionKitTests → swiftkit/Sources/PermissionKit
        let base = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PermissionKit")
        return try String(contentsOf: base.appendingPathComponent(relative), encoding: .utf8)
    }
}

/// 좀비 정리의 **소유 경계**.
///
/// 실측 2026-08-08: "번들이 없으면 죽었다" 만으로 판정하니 164건이 나왔고 그 안에
/// `com.apple.ScreenTimeAgent`, `com.apple.accessibility.AccessibilityUIServer` 같은
/// 시스템 데몬 47건이 섞였다. 데몬·XPC 는 `.app` 이 아니라 LaunchServices 로 해석되지
/// 않을 뿐 살아 있다 — 지우면 macOS 기능이 깨진다. 이 경계가 무너지면 위험한 도구가 된다.
final class PrunerOwnershipTests: XCTestCase {

    func testAppleSystemClientsAreNeverOwned() {
        for client in ["com.apple.ScreenTimeAgent", "com.apple.accessibility.AccessibilityUIServer",
                       "com.apple.StatusKitAgent", "com.apple.avatarsd"] {
            XCTAssertFalse(
                TCCPruner.isOwned(client, prefixes: TCCPruner.ownedBundlePrefixes),
                "\(client) 는 시스템 데몬이다 — 정리 대상이 되면 안 된다")
        }
    }

    func testThirdPartyClientsAreNotOwned() {
        for client in ["com.openai.chat", "com.googlecode.iterm2", "com.adobe.PremierePro.25",
                       "Mattermost.Desktop"] {
            XCTAssertFalse(TCCPruner.isOwned(client, prefixes: TCCPruner.ownedBundlePrefixes),
                           "\(client): 서드파티는 우리가 판단할 근거가 없다")
        }
    }

    func testOurFleetBundlesAreOwned() {
        for client in ["net.ranode.screenshotswift.dev", "com.dalsoop.AgentSSOT",
                       "local.vibecli-mapper", "net.ranode.rightclick.dev"] {
            XCTAssertTrue(TCCPruner.isOwned(client, prefixes: TCCPruner.ownedBundlePrefixes),
                          "\(client) 는 우리 함대다")
        }
    }

    /// 접두어 목록이 비면 아무것도 소유하지 않는다 — 실수로 전부 지우는 경로를 막는다.
    func testEmptyPrefixListOwnsNothing() {
        XCTAssertFalse(TCCPruner.isOwned("net.ranode.anything", prefixes: []))
    }
}
