import Darwin
import XCTest
@testable import StateMirrorKit

/// 종료 정책의 계약을 고정한다.
///
/// 배경: 미러를 게시하는 앱 17개 중 16개가 종료 훅을 안 붙여, 앱이 죽은 뒤에도 마지막 상태가
/// 사실처럼 남았다. 정책을 키트로 옮기되 **"무엇을 지울지" 는 앱이 고르게** 한다 — 일괄로
/// 지우면 pim-* 처럼 미러가 곧 데이터인 앱을 깨뜨린다.
final class TerminationPolicyTests: XCTestCase {
    private var appName: String { "TerminationPolicyTests-\(UUID().uuidString)" }

    private func read(_ app: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: StateMirror.path(app: app)) else { return nil }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?["state"] as? [String: Any]
    }

    /// 미러 전체가 라이브 상태인 앱(MenuFold 의 fold) — 앱이 없으면 그 상태도 없다.
    func testClearPolicyRemovesMirror() {
        let app = appName
        StateMirror.publishJSONObject(app: app, ["fold": "collapsed"])
        XCTAssertNotNil(read(app), "사전 조건")

        StateMirror.applyTerminationPolicy(app: app, .clear)

        XCTAssertNil(read(app), "clear 정책인데 미러가 남으면 소비자가 낡은 상태를 현재로 읽는다")
    }

    /// 라이브 플래그가 데이터와 섞인 앱(RecordTimelabs 의 state/busy + 녹화 목록) —
    /// 지우면 데이터까지 날아가므로 플래그만 사실대로 덮어쓰고 나머지는 그대로 둔다.
    func testPatchFinalCorrectsLiveFlagsButKeepsData() throws {
        let app = appName
        defer { StateMirror.clear(app: app) }

        StateMirror.publishJSONObject(app: app, [
            "state": "recording", "busy": true,
            "recordingCount": 3, "lastRecording": "a.mov",
        ])

        // 앱은 바꿀 키만 선언한다 — 상태를 다시 계산하지 않으므로 모델(@MainActor)을 안 붙잡는다.
        StateMirror.applyTerminationPolicy(app: app, .patchFinal(["state": "idle", "busy": false]))

        let state = try XCTUnwrap(read(app), "patchFinal 정책은 미러를 남겨야 한다")
        XCTAssertEqual(state["state"] as? String, "idle", "라이브 플래그가 사실대로 고쳐지지 않았다")
        XCTAssertEqual(state["busy"] as? Bool, false)
        XCTAssertEqual(state["recordingCount"] as? Int, 3, "선언 안 한 데이터까지 건드리면 안 된다")
        XCTAssertEqual(state["lastRecording"] as? String, "a.mov")
    }

    /// 게시된 적 없는 앱에 patch 를 걸어도 조용히 넘어간다(남길 데이터 자체가 없다).
    func testPatchFinalOnUnpublishedAppDoesNothing() {
        let app = appName
        StateMirror.applyTerminationPolicy(app: app, .patchFinal(["state": "idle"]))
        XCTAssertNil(read(app), "게시된 적 없는데 patch 가 미러를 만들어내면 안 된다")
    }

    /// patchFinal은 lock을 얻은 뒤 최신 상태를 읽어야 한다. 그렇지 않으면 종료 직전 다른
    /// writer가 게시한 데이터 필드를 낡은 snapshot으로 되감는다.
    func testPatchFinalReadsLatestStateAfterLockAcquisition() async throws {
        let app = appName
        defer { StateMirror.clear(app: app) }
        StateMirror.publishJSONObject(app: app, [
            "state": "recording",
            "recordingCount": 1,
        ])
        let mirrorURL = URL(fileURLWithPath: StateMirror.path(app: app))
        let lockURL = URL(fileURLWithPath: mirrorURL.path + ".lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        XCTAssertEqual(flock(descriptor, LOCK_EX), 0)

        let started = expectation(description: "patchFinal task started")
        let mutation = Task.detached {
            started.fulfill()
            StateMirror.applyTerminationPolicy(
                app: app,
                .patchFinal(["state": "idle"])
            )
        }
        await fulfillment(of: [started], timeout: 2)
        try await Task.sleep(for: .milliseconds(30))

        let latestEnvelope: [String: Any] = [
            "app": app,
            "updatedAt": "2026-07-24T00:00:00Z",
            "state": [
                "state": "recording",
                "recordingCount": 2,
                "lastRecording": "latest.mov",
            ],
        ]
        let latestData = try JSONSerialization.data(
            withJSONObject: latestEnvelope,
            options: [.prettyPrinted, .sortedKeys]
        )
        try latestData.write(to: mirrorURL, options: .atomic)
        XCTAssertEqual(flock(descriptor, LOCK_UN), 0)
        close(descriptor)
        await mutation.value

        let state = try XCTUnwrap(read(app))
        XCTAssertEqual(state["state"] as? String, "idle")
        XCTAssertEqual(state["recordingCount"] as? Int, 2)
        XCTAssertEqual(state["lastRecording"] as? String, "latest.mov")
    }

    /// 등록만으로는 아무 일도 일어나지 않는다 — 종료 알림이 와야 적용된다.
    /// (CLI 프로세스엔 NSApplication 이 없어 알림 자체가 발생하지 않으므로, 데이터 미러가 안전하다.)
    func testRegisteringDoesNotApplyImmediately() {
        let app = appName
        defer { StateMirror.clear(app: app) }
        StateMirror.publishJSONObject(app: app, ["todos": ["a", "b"]])

        StateMirror.onTerminate(app: app, .clear)

        XCTAssertEqual(
            read(app)?["todos"] as? [String], ["a", "b"],
            "등록만으로 지워지거나 바뀌면 CLI 가 게시한 데이터가 즉시 사라진다")
    }

    /// 종료 알림이 오면 등록된 정책이 적용된다(알림 이름은 AppKit 없이 문자열로 구독한다).
    func testTerminateNotificationAppliesRegisteredPolicy() {
        let app = appName
        StateMirror.publishJSONObject(app: app, ["fold": "collapsed"])
        StateMirror.onTerminate(app: app, .clear)

        NotificationCenter.default.post(
            name: Notification.Name("NSApplicationWillTerminateNotification"), object: nil
        )

        XCTAssertNil(read(app), "종료 알림에도 정책이 적용되지 않았다 — 훅 배선이 끊겼다")
    }
}
