import XCTest
@testable import PermissionKit

/// 행위로 잰다 — 상수를 다시 적어 비교하면 오타까지 같이 통과한다.
final class LoginItemsSettingsTests: XCTestCase {
    /// 후보는 전부 실제 URL 이어야 한다. 문자열만 맞고 `URL(string:)` 이 nil 이면
    /// 열기 루프가 조용히 전부 건너뛴다.
    func testEveryCandidateParsesAsURL() {
        let candidates = LoginItemsSettings.settingsURLCandidates
        XCTAssertGreaterThanOrEqual(candidates.count, 2, "폴백이 있어야 한다")
        for candidate in candidates {
            XCTAssertNotNil(URL(string: candidate), "URL 이 아니다: \(candidate)")
        }
    }

    /// 정규 앵커가 첫 후보다 — 가장 정확한 화면을 먼저 시도한다.
    func testCanonicalAnchorComesFirst() {
        XCTAssertEqual(LoginItemsSettings.settingsURLCandidates.first,
                       LoginItemsSettings.settingsURLString)
    }

    /// 첫 후보가 열리면 그걸 돌려주고 뒤는 시도하지 않는다.
    @MainActor
    func testOpenSettingsStopsAtFirstSuccess() {
        var tried: [String] = []
        let opened = LoginItemsSettings.openSettings { url in
            tried.append(url.absoluteString)
            return true
        }
        XCTAssertEqual(opened, LoginItemsSettings.settingsURLString)
        XCTAssertEqual(tried.count, 1, "성공했는데 뒤 후보까지 열었다: \(tried)")
    }

    /// 전부 실패하면 nil 이다 — 호출측이 수동 안내로 넘어갈 수 있어야 한다.
    /// 여기서 true 를 돌려주면 "열렸다"고 믿고 사용자는 빈 화면 앞에 남는다.
    @MainActor
    func testOpenSettingsReturnsNilWhenNothingOpens() {
        var tried: [String] = []
        let opened = LoginItemsSettings.openSettings { url in
            tried.append(url.absoluteString)
            return false
        }
        XCTAssertNil(opened)
        XCTAssertEqual(tried, LoginItemsSettings.settingsURLCandidates, "후보를 다 시도해야 한다")
    }

    /// 딥링크 실패 안내는 사람이 손으로 갈 경로를 담는다.
    func testManualHintNamesTheScreen() {
        XCTAssertTrue(LoginItemsSettings.manualNavigationHint(language: .korean)
            .contains("로그인 항목"))
        XCTAssertTrue(LoginItemsSettings.manualNavigationHint(language: .english)
            .contains("Login Items"))
    }

    /// 시스템 확장 안내도 같은 앵커를 쓴다.
    ///
    /// `SystemExtension` 은 아직 이 상수를 참조하지 않고 같은 문자열을 자기 목록에 들고
    /// 있다 — 그 파일엔 이 MR 과 무관한 lint 결함 2건(`direct-process-in-core`,
    /// `global-dispatch-queue`)이 있어 한 줄만 고쳐도 무관한 수리가 딸려 온다.
    /// 참조로 묶기 전까지 **이 테스트가 드리프트 감시자**다.
    func testSystemExtensionReusesTheSameAnchor() {
        XCTAssertTrue(SystemExtension.settingsURLCandidates.contains(LoginItemsSettings.settingsURLString),
                      "SystemExtension 이 SSOT 앵커를 안 쓴다: \(SystemExtension.settingsURLCandidates)")
    }
}

/// `SystemExtension.shell` 이 stderr 를 드레인하는지 **행위로** 확인한다.
///
/// 옛 구현은 stderr 파이프를 만들어만 두고 읽지 않았다. 자식이 파이프 버퍼(64KB)를
/// 넘겨 쓰면 그 write 에서 막히고, 부모는 stdout 의 `readDataToEndOfFile()` 에서 같이
/// 막힌다. 30초 타이머는 **그 줄 다음에** 걸리므로 아예 스케줄되지 않는다 —
/// 타임아웃 없는 영구 교착이다(2026-09-06 변이 실측: 테스트 프로세스가 10분 넘게
/// 살아 있었고, 자식과 손자까지 그대로 남았다).
///
/// 그래서 회귀는 "빨간 실패" 가 아니라 **행** 으로 나타난다. 형제 테스트
/// `TCCReaderTests.testLargeResultDoesNotDeadlockOnPipeBuffer` 도 같은 형태다 —
/// 이 함대에서 파이프 교착을 재는 방식이다. 자식은 `printf` 빌트인만 쓰는 단일
/// 프로세스라, 잡 타임아웃이 끊을 때 고아 손자를 남기지 않는다.
final class SystemExtensionShellDrainTests: XCTestCase {
    func testStdoutSurvivesALoudStderr() {
        // 512KB 를 stderr 로 쏟고 나서 stdout 에 표식을 찍는다.
        // 드레인이 없으면 자식이 첫 64KB 에서 막혀 표식이 영원히 오지 않는다.
        let script = "i=0; while [ $i -lt 512 ]; do printf '%01024d' 0 >&2; i=$((i+1)); done; echo DONE-MARKER"
        let out = SystemExtension.shell("/bin/sh", ["-c", script])
        XCTAssertTrue(out.contains("DONE-MARKER"),
                      "stderr 가 시끄러우면 stdout 이 잘린다 — 드레인이 빠졌다: \(out.prefix(200))")
    }

    func testDeepCandidateIsTheSSOTAnchorPlusFilter() {
        XCTAssertEqual(SystemExtension.settingsURLCandidates.first,
                       LoginItemsSettings.settingsURLString
                           + "?extensionPointIdentifier=com.apple.system_extension.network_extension")
    }
}
