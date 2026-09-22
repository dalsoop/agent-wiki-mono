import XCTest
@testable import GujoStoreOpsCore

#if os(macOS)
final class AdbDiagnosisTests: XCTestCase {
    func testParseUnauthorizedPreserved() {
        let out = """
        List of devices attached
        R58M123 unauthorized
        emulator-5554 device product:sdk model:sdk_gphone64_arm64
        """
        let devs = AdbClient.parseDevices(out)
        XCTAssertEqual(devs.count, 2)
        XCTAssertEqual(devs[0].state, "unauthorized")
        XCTAssertTrue(devs[0].isUnauthorized)
        XCTAssertFalse(devs[0].isReady)
        XCTAssertEqual(devs[1].state, "ready")
        XCTAssertTrue(devs[1].isReady)
        XCTAssertTrue(devs[1].isEmulator)
    }

    func testClassifyNoDevices() {
        let d = AdbDiagnosis.classify(adbAvailable: true, adbPath: "/opt/homebrew/bin/adb", devices: [])
        XCTAssertEqual(d.kind, .noDevices)
        XCTAssertFalse(d.isReady)
    }

    func testClassifyUnauthorized() {
        let dev = OpsDevice(id: "x", label: "x", serial: "x", state: "unauthorized")
        let d = AdbDiagnosis.classify(adbAvailable: true, adbPath: "adb", devices: [dev])
        XCTAssertEqual(d.kind, .unauthorized)
    }

    func testListedDeviceWithoutShellIsDead() {
        let dev = OpsDevice(id: "e", label: "e", serial: "emulator-5554", state: "ready")
        let d = AdbDiagnosis.classify(
            adbAvailable: true, adbPath: "adb", devices: [dev], shellOkSerials: []
        )
        XCTAssertEqual(d.kind, .listedButShellDead)
        XCTAssertFalse(d.isReady)
        XCTAssertEqual(d.listedReadyCount, 1)
        XCTAssertEqual(d.shellOkCount, 0)
    }

    func testShellOkIsReady() {
        let dev = OpsDevice(id: "e", label: "e", serial: "emulator-5554", state: "ready")
        let d = AdbDiagnosis.classify(
            adbAvailable: true, adbPath: "adb", devices: [dev],
            shellOkSerials: ["emulator-5554"]
        )
        XCTAssertEqual(d.kind, .ready)
        XCTAssertTrue(d.isReady)
        XCTAssertTrue(d.onlyEmulator)
        XCTAssertEqual(d.physicalShellOkCount, 0)
    }

    func testPhysicalShellOk() {
        let dev = OpsDevice(id: "R1", label: "phone", serial: "R1", state: "ready")
        let d = AdbDiagnosis.classify(
            adbAvailable: true, adbPath: "adb", devices: [dev],
            shellOkSerials: ["R1"]
        )
        XCTAssertTrue(d.isReady)
        XCTAssertFalse(d.onlyEmulator)
        XCTAssertEqual(d.physicalShellOkCount, 1)
    }

    func testClassifyMissingAdb() {
        let d = AdbDiagnosis.classify(adbAvailable: false, adbPath: "adb", devices: [])
        XCTAssertEqual(d.kind, .adbMissing)
    }
}
#endif
