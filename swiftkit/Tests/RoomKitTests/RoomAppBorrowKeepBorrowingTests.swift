import Foundation
import Testing
import RoomPlacementKit
@testable import RoomKit

@Suite("RoomAppBorrow 5-minute keep-borrowing")
struct RoomAppBorrowKeepBorrowingTests {
    private let agent = RoomActor.agent(name: "grok", sessionID: "sess-keep-borrow")
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func borrow(
        roomID: String = "room-keep",
        bundleID: String,
        at start: Date
    ) -> RoomAppBorrow {
        RoomAppBorrow(
            roomID: roomID,
            bundleID: bundleID,
            agent: agent,
            borrowedAt: start,
            duration: RoomAppBorrowClock.keepDuration
        )
    }

    @Test("borrow at t=0 is active at 4:59 and inactive at 5:01")
    func borrowActiveUntilJustUnderFiveMinutes() {
        let lease = borrow(bundleID: "net.ranode.agent-browser", at: t0)
        let fourFiftyNine = t0.addingTimeInterval(4 * 60 + 59)
        let fiveOhOne = t0.addingTimeInterval(5 * 60 + 1)

        #expect(RoomAppBorrowClock.keepDuration == 5 * 60)
        #expect(lease.expiresAt == RoomAppBorrowClock.expiresAt(from: t0))
        #expect(lease.isActive(now: t0))
        #expect(lease.isActive(now: fourFiftyNine))
        #expect(!lease.isActive(now: fiveOhOne))
        #expect(RoomAppBorrowClock.isActive(status: .active, expiresAt: lease.expiresAt, now: fourFiftyNine))
        #expect(!RoomAppBorrowClock.isActive(status: .active, expiresAt: lease.expiresAt, now: fiveOhOne))
    }

    @Test("renew at t=4:00 stays active at 8:50 and is dead at 9:01")
    func renewAtFourMinutesExtendsKeepWindow() {
        var lease = borrow(bundleID: "net.ranode.agent-browser", at: t0)
        let renewAt = t0.addingTimeInterval(4 * 60)
        lease.renew(now: renewAt, duration: RoomAppBorrowClock.keepDuration)

        let eightFifty = t0.addingTimeInterval(8 * 60 + 50)
        let nineOhOne = t0.addingTimeInterval(9 * 60 + 1)

        #expect(lease.borrowedAt == t0)
        #expect(lease.expiresAt == RoomAppBorrowClock.expiresAt(from: renewAt))
        #expect(lease.isActive(now: eightFifty))
        #expect(!lease.isActive(now: nineOhOne))
    }

    @Test("two apps in one room keep independent clocks")
    func twoAppsInOneRoomHaveIndependentClocks() {
        let roomID = "room-pair"
        let browser = borrow(roomID: roomID, bundleID: "net.ranode.agent-browser", at: t0)
        var terminal = borrow(
            roomID: roomID,
            bundleID: "net.ranode.agent-room-terminal",
            at: t0.addingTimeInterval(2 * 60)
        )

        let fourFiftyNine = t0.addingTimeInterval(4 * 60 + 59)
        let fiveOhOne = t0.addingTimeInterval(5 * 60 + 1)
        #expect(browser.isActive(now: fourFiftyNine))
        #expect(terminal.isActive(now: fourFiftyNine))
        #expect(!browser.isActive(now: fiveOhOne))
        #expect(terminal.isActive(now: fiveOhOne))

        let sevenOhOne = t0.addingTimeInterval(7 * 60 + 1)
        #expect(!terminal.isActive(now: sevenOhOne))

        terminal.renew(now: t0.addingTimeInterval(6 * 60), duration: RoomAppBorrowClock.keepDuration)
        #expect(!browser.isActive(now: t0.addingTimeInterval(6 * 60 + 1)))
        #expect(terminal.isActive(now: t0.addingTimeInterval(10 * 60 + 50)))
        #expect(!terminal.isActive(now: t0.addingTimeInterval(11 * 60 + 1)))
    }

    @Test("expired borrow is not room membership for Dock observation")
    func expiredBorrowIsNotDockRoomMembership() {
        let roomID = "room-dock"
        let liveID = "net.ranode.agent-browser"
        let staleID = "net.ranode.gitlab-manager"
        let otherRoomID = "net.ranode.agent-room-terminal"
        var live = borrow(roomID: roomID, bundleID: liveID, at: t0)
        let stale = borrow(roomID: roomID, bundleID: staleID, at: t0)
        let otherRoom = borrow(roomID: "room-other", bundleID: otherRoomID, at: t0)

        live.renew(now: t0.addingTimeInterval(4 * 60), duration: RoomAppBorrowClock.keepDuration)
        let now = t0.addingTimeInterval(5 * 60 + 1)
        let members = RoomAppBorrow.dockObservedBundleIDs(
            roomID: roomID,
            borrows: [live, stale, otherRoom],
            now: now
        )

        #expect(members == [liveID])
        #expect(!stale.isActive(now: now))
        #expect(!members.contains(staleID))
        #expect(!members.contains(otherRoomID))
        #expect(RoomAppBorrow.dockObservedBundleIDs(roomID: roomID, borrows: [stale], now: now).isEmpty)
    }
}
