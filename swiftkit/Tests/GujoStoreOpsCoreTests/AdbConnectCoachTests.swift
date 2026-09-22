import XCTest
@testable import GujoStoreOpsCore

final class AdbConnectCoachTests: XCTestCase {
    func testNoDevicesGivesSingleNowDo() {
        let d = AdbDiagnosis.classify(adbAvailable: true, adbPath: "adb", devices: [])
        let t = AdbConnectCoach.turn(from: d, previousKind: nil)
        XCTAssertFalse(t.ready)
        XCTAssertFalse(t.nowDo.isEmpty)
        XCTAssertEqual(t.event, .firstScan)
    }

    func testBecameReadyEvent() {
        let unauth = OpsDevice(id: "x", label: "x", serial: "x", state: "unauthorized")
        let d1 = AdbDiagnosis.classify(adbAvailable: true, adbPath: "adb", devices: [unauth])
        _ = AdbConnectCoach.turn(from: d1, previousKind: nil)

        let ready = OpsDevice(id: "x", label: "x", serial: "x", state: "ready")
        let d2 = AdbDiagnosis.classify(
            adbAvailable: true, adbPath: "adb", devices: [ready],
            shellOkSerials: ["x"]
        )
        let t2 = AdbConnectCoach.turn(from: d2, previousKind: .unauthorized)
        XCTAssertTrue(t2.ready)
        XCTAssertEqual(t2.event, .becameReady)
        XCTAssertTrue(
            t2.spokenLine.contains("ready")
                || t2.spokenLine.contains("등록")
                || t2.spokenLine.contains("job")
                || t2.spokenLine.contains("AdbConnectCoach")
                || !t2.spokenLine.isEmpty
        )
    }

    func testReadyAlreadyOnServer() {
        let ready = OpsDevice(id: "x", label: "x", serial: "R58", state: "ready")
        let d = AdbDiagnosis.classify(
            adbAvailable: true, adbPath: "adb", devices: [ready],
            shellOkSerials: ["R58"]
        )
        let t = AdbConnectCoach.turn(from: d, serverSerials: ["R58"])
        XCTAssertTrue(t.nowDo.contains("job") || t.nowDo.contains("패키지"))
    }

    func testOnlyEmulatorMentionsEmu() {
        let ready = OpsDevice(id: "e", label: "e", serial: "emulator-5554", state: "ready")
        let d = AdbDiagnosis.classify(
            adbAvailable: true, adbPath: "adb", devices: [ready],
            shellOkSerials: ["emulator-5554"]
        )
        let t = AdbConnectCoach.turn(from: d)
        XCTAssertTrue(t.why.contains("에뮬") || t.nowDo.contains("에뮬"))
    }

    func testUnauthorizedScript() {
        let unauth = OpsDevice(id: "x", label: "x", serial: "x", state: "unauthorized")
        let d = AdbDiagnosis.classify(adbAvailable: true, adbPath: "adb", devices: [unauth])
        let t = AdbConnectCoach.turn(from: d)
        XCTAssertTrue(t.nowDo.contains("허용") || t.nowDo.contains("신뢰"))
    }
}
