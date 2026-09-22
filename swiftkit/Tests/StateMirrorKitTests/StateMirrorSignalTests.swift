import Darwin
import Foundation
import XCTest
@testable import StateMirrorKit

final class StateMirrorSignalTests: XCTestCase {
    func testSignalNotificationNameFormat() {
        let name = StateMirrorSignal.notificationName(for: "vibecode-custom-cli")
        XCTAssertEqual(name, "com.gujo.statemirror.vibecode-custom-cli")
    }

    func testSignalPostAndWatcherCatchNotification() {
        let app = "test-signal-app-\(UUID().uuidString)"
        let exp = expectation(description: "Watcher should receive notification")

        let watcher = StateMirrorWatcher(app: app, queue: .main) {
            exp.fulfill()
        }

        let posted = StateMirrorSignal.post(app: app)
        XCTAssertTrue(posted)

        wait(for: [exp], timeout: 2.0)
        watcher.cancel()
    }

    func testWatcherPublisherEmitsEvent() {
        let app = "test-publisher-app-\(UUID().uuidString)"
        let exp = expectation(description: "Publisher should emit event")

        let watcher = StateMirrorWatcher(app: app, queue: .main)
        var cancellable: Any? = watcher.publisher.sink { _ in
            exp.fulfill()
        }
        _ = cancellable

        let posted = StateMirrorSignal.post(app: app)
        XCTAssertTrue(posted)

        wait(for: [exp], timeout: 2.0)
        watcher.cancel()
        cancellable = nil
    }

    func testAtomicFilePresenterWritesData() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("atomic-test.json")
        let data = "{\"hello\":\"world\"}".data(using: .utf8)!

        try StateMirrorFilePresenter.atomicWrite(data: data, to: fileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let readData = try Data(contentsOf: fileURL)
        XCTAssertEqual(readData, data)
    }

    func testPublishAutomaticallyPostsSignal() {
        let app = "auto-signal-app-\(UUID().uuidString)"
        let exp = expectation(description: "Watcher should be triggered on StateMirror.publish")

        let watcher = StateMirrorWatcher(app: app, queue: .main) {
            exp.fulfill()
        }

        StateMirror.publish(app: app, ["status": "active"])

        wait(for: [exp], timeout: 2.0)
        watcher.cancel()
    }
}
