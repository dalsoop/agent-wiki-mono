import ApplicationServices
import CoreGraphics
import XCTest
@testable import AXTreeKit

/// AX 트리의 **값**(실제 UI 의 role·title·frame)은 화면 세션과 접근성 권한이 있어야 읽힌다.
/// 그래서 여기서는 권한과 무관하게 성립하는 계약만 잰다 — 엘리먼트 신원, 속성 실패의 nil 변환,
/// 타입 가드, 그리고 프롬프트 없는 권한 조회. 예전 버전은 `_ = ...` 로 호출만 하고 끝나
/// 어떤 회귀도 잡지 못했다.
final class AXTreeKitTests: XCTestCase {
    /// 존재하지 않을 pid — 이 프로세스 트리 밖이라 어떤 속성도 성공하지 않는다.
    private let absentPID: pid_t = 0x7FFF_FFFE

    func testSystemWideElementIsAnAXUIElementAndIsStableAcrossCalls() {
        let first = AXTree.systemWide()
        let second = AXTree.systemWide()

        XCTAssertEqual(CFGetTypeID(first), AXUIElementGetTypeID(), "systemWide 가 AXUIElement 가 아니면 이후 모든 헬퍼가 무의미하다")
        XCTAssertTrue(CFEqual(first, second), "system-wide 엘리먼트는 호출마다 같은 대상을 가리켜야 한다")
    }

    func testApplicationElementIdentityFollowsThePID() {
        let mine = AXTree.application(pid: getpid())
        let mineAgain = AXTree.application(pid: getpid())
        let other = AXTree.application(pid: absentPID)

        XCTAssertTrue(CFEqual(mine, mineAgain), "같은 pid 는 같은 앱 엘리먼트여야 한다")
        XCTAssertFalse(CFEqual(mine, other), "다른 pid 가 같은 엘리먼트로 접히면 앱 구분이 사라진다")
    }

    func testUnsupportedAttributeBecomesNilInsteadOfGarbage() {
        let value = AXTree.copyAttribute(AXTree.systemWide(), "AXAttributeThatDoesNotExist")

        XCTAssertNil(value, "실패한 AXUIElementCopyAttributeValue 의 미초기화 out 파라미터를 그대로 돌려주면 안 된다")
    }

    func testElementAccessorRejectsAttributesThatAreNotElements() {
        // kAXRole 은 문자열이다 — 타입 가드가 없으면 as! 캐스팅에서 크래시한다.
        XCTAssertNil(AXTree.element(AXTree.systemWide(), kAXRoleAttribute as String))
        XCTAssertNil(AXTree.string(AXTree.systemWide(), kAXChildrenAttribute as String))
    }

    func testAbsentApplicationYieldsEmptyChildrenAndNoGeometry() {
        let absent = AXTree.application(pid: absentPID)

        XCTAssertEqual(AXTree.children(absent).count, 0, "속성을 못 읽으면 빈 배열이어야 한다 — nil 을 [] 로 접는 계약")
        XCTAssertNil(AXTree.title(absent))
        XCTAssertNil(AXTree.role(absent))
        XCTAssertNil(AXTree.parent(absent))
        XCTAssertNil(AXTree.point(absent, kAXPositionAttribute as String))
        XCTAssertNil(AXTree.size(absent, kAXSizeAttribute as String))
        XCTAssertNil(AXTree.frame(absent), "position·size 중 하나라도 없으면 frame 은 nil 이다")
    }

    func testFocusChainIsNilForAnAbsentApplication() {
        XCTAssertNil(AXTree.focusedWindow(pid: absentPID))
    }

    func testIsTrustedMatchesTheFrameworkAndNeverPrompts() {
        // 프롬프트를 띄우는 AXIsProcessTrustedWithOptions 로 바뀌면 헤드리스 CI 가 멈춘다.
        let trusted = AXTree.isTrusted

        XCTAssertEqual(trusted, AXIsProcessTrusted())
        XCTAssertEqual(trusted, AXTree.isTrusted, "권한 조회는 부작용 없이 같은 값을 내야 한다")
    }
}
