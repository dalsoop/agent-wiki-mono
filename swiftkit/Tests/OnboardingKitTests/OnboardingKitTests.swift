import XCTest
@testable import OnboardingKit

final class OnboardingKitTests: XCTestCase {
    func testMissingRequiredItems() {
        let snap = OnboardingSnapshot(
            items: [
                OnboardingItem(id: "a", done: false),
                OnboardingItem(id: "b", done: true),
                OnboardingItem(id: "c", done: false, required: false),
            ],
            dismissed: false
        )
        XCTAssertEqual(snap.missing, ["a"])
        XCTAssertFalse(snap.satisfied)
        XCTAssertFalse(snap.complete)
        XCTAssertTrue(snap.shouldPresent)
    }

    func testSatisfiedHidesGate() {
        let snap = OnboardingSnapshot(
            items: [OnboardingItem(id: "a", done: true)],
            dismissed: false
        )
        XCTAssertTrue(snap.satisfied)
        XCTAssertFalse(snap.shouldPresent)
    }

    func testDismissedSkipsEvenIfMissing() {
        let snap = OnboardingSnapshot(
            items: [OnboardingItem(id: "a", done: false)],
            dismissed: true
        )
        XCTAssertFalse(snap.satisfied)
        XCTAssertFalse(snap.shouldPresent)
    }
}
