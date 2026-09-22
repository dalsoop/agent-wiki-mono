import XCTest
@testable import PhotoLedgerKit

final class PhotoLedgerKitTests: XCTestCase {
    func testShareRootFileURLJoins() {
        let url = LedgerShareRoot.fileURL(shareRoot: "/tmp/share", rel: "a/b.jpg")
        XCTAssertTrue(url.path.hasSuffix("/a/b.jpg"))
    }

    func testBlobRefIdentity() {
        let blob = LedgerBlobRef(id: "ab", sessionId: "s", name: "a.jpg", rel: "s/a.jpg")
        XCTAssertEqual(blob.id, "ab")
    }

    func testOnboardingJudgeComplete() {
        let missing = OnboardingJudge.evaluate(ledgerInstalled: false, ledgerReady: false, dismissed: false)
        XCTAssertFalse(missing.complete)
        let ready = OnboardingJudge.evaluate(ledgerInstalled: true, ledgerReady: true, dismissed: false)
        XCTAssertTrue(ready.complete)
        let skipped = OnboardingJudge.evaluate(ledgerInstalled: false, ledgerReady: false, dismissed: true)
        XCTAssertTrue(skipped.dismissed)
        XCTAssertFalse(skipped.shouldPresent)
    }
}
