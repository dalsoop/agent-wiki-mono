import XCTest
@testable import GujoStoreOpsCore

final class PhoneConnectionPlaybookTests: XCTestCase {
    func testStepsCoverPhoneUI() {
        let ids = PhoneConnectionPlaybook.steps.map(\.id)
        XCTAssertTrue(ids.contains("developer-options"))
        XCTAssertTrue(ids.contains("usb-debugging"))
        XCTAssertTrue(ids.contains("trust-dialog"))
        XCTAssertTrue(ids.contains("cable"))
        let text = PhoneConnectionPlaybook.plainText()
        XCTAssertTrue(text.contains("USB 디버깅"))
        XCTAssertTrue(text.contains("빌드번호"))
    }

    func testPhysicalPassWhenShellPhysical() {
        let step = PhoneConnectionPlaybook.steps.first { $0.id == "trust-dialog" }!
        let empty = AdbDiagnosis.classify(adbAvailable: true, adbPath: "adb", devices: [])
        XCTAssertFalse(PhoneConnectionPlaybook.isStepPassed(step, diagnosis: empty))

        let phys = OpsDevice(id: "R1", label: "phone", serial: "R1", state: "ready")
        let d = AdbDiagnosis.classify(
            adbAvailable: true, adbPath: "adb", devices: [phys],
            shellOkSerials: ["R1"]
        )
        XCTAssertTrue(PhoneConnectionPlaybook.isStepPassed(step, diagnosis: d))
    }

    func testCablePassWhenAnyListed() {
        let step = PhoneConnectionPlaybook.steps.first { $0.id == "cable" }!
        let unauth = OpsDevice(id: "x", label: "x", serial: "x", state: "unauthorized")
        let d = AdbDiagnosis.classify(adbAvailable: true, adbPath: "adb", devices: [unauth])
        XCTAssertTrue(PhoneConnectionPlaybook.isStepPassed(step, diagnosis: d))
    }
}
