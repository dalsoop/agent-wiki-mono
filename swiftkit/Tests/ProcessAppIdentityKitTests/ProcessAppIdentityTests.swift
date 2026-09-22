import XCTest
@testable import ProcessAppIdentityKit

final class ProcessAppIdentityTests: XCTestCase {
    func testApplicationRootFromHelperPath() {
        XCTAssertEqual(
            ProcessAppIdentity.applicationRoot(
                fromExecutable: "/Applications/Agent Work Todo.app/Contents/Helpers/agent-work-todo"
            ),
            "/Applications/Agent Work Todo.app"
        )
    }

    func testApplicationRootNilForSystemDaemon() {
        XCTAssertNil(ProcessAppIdentity.applicationRoot(fromExecutable: "/usr/sbin/WindowServer"))
        XCTAssertNil(
            ProcessAppIdentity.applicationRoot(
                fromExecutable: "/System/Library/Frameworks/CoreServices.framework/Support/mds"
            )
        )
    }

    func testApplicationRootExactAppPath() {
        XCTAssertEqual(
            ProcessAppIdentity.applicationRoot(fromExecutable: "/Applications/Safari.app"),
            "/Applications/Safari.app"
        )
    }
}
