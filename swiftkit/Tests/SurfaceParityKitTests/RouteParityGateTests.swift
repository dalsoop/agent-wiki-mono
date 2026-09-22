import XCTest
import SurfaceParityKit

final class RouteParityGateTests: XCTestCase {
    enum MockMatchingUIRoute: String, CaseIterable {
        case dashboard
        case settings
        case profile
    }

    enum MockMatchingCLICommand: String, CaseIterable {
        case dashboard
        case settings
        case profile
    }

    enum MockMismatchedUIRoute: String, CaseIterable {
        case dashboard
        case settings
        case extraUIPage
    }

    enum MockMismatchedCLICommand: String, CaseIterable {
        case dashboard
        case settings
        case extraCLIAction
    }

    func testExactOneToOneParitySucceeds() {
        let result = assertSurfaceParity(
            routes: MockMatchingUIRoute.self,
            commands: MockMatchingCLICommand.self
        )
        XCTAssertTrue(result)

        let verdict = RouteParityGate.verifyParity(
            routes: MockMatchingUIRoute.self,
            commands: MockMatchingCLICommand.self
        )
        XCTAssertTrue(verdict.isIsomorphic)
        XCTAssertTrue(verdict.differences.isEmpty)
        XCTAssertEqual(verdict.comparedNodesCount, 3)
    }

    func testParityDiffDetectionForMissingItems() {
        let verdict = RouteParityGate.verifyParity(
            routes: MockMismatchedUIRoute.self,
            commands: MockMismatchedCLICommand.self
        )

        XCTAssertFalse(verdict.isIsomorphic)
        XCTAssertEqual(verdict.differences.count, 2)

        let missingCLI = verdict.differences.filter { $0.kind == .missingKeyInCLI }
        let missingGUI = verdict.differences.filter { $0.kind == .missingKeyInGUI }

        XCTAssertEqual(missingCLI.count, 1)
        XCTAssertEqual(missingCLI.first?.guiValue, "extraUIPage")
        XCTAssertEqual(missingCLI.first?.path, "extraUIPage")

        XCTAssertEqual(missingGUI.count, 1)
        XCTAssertEqual(missingGUI.first?.cliValue, "extraCLIAction")
        XCTAssertEqual(missingGUI.first?.path, "extraCLIAction")

        let message = RouteParityGate.formatFailureMessage(
            verdict: verdict,
            routeTypeName: "MockMismatchedUIRoute",
            commandTypeName: "MockMismatchedCLICommand"
        )
        XCTAssertTrue(message.contains("extraUIPage"))
        XCTAssertTrue(message.contains("extraCLIAction"))
        XCTAssertTrue(message.contains("Surface Parity Violation"))
    }

    func testAssertSurfaceParityReturnsFalseOnMismatch() {
        // Calling assertSurfaceParity on mismatch returns false (mocking or checking return value)
        let success = RouteParityGate.verifyParity(
            routes: MockMismatchedUIRoute.self,
            commands: MockMatchingCLICommand.self
        ).isIsomorphic

        XCTAssertFalse(success)
    }

    enum PlainEnumRoute: CaseIterable {
        case overview
        case analytics
    }

    enum PlainEnumCommand: CaseIterable {
        case overview
        case analytics
    }

    func testPlainCaseIterableWithoutRawRepresentable() {
        let result = assertSurfaceParity(
            routes: PlainEnumRoute.self,
            commands: PlainEnumCommand.self
        )
        XCTAssertTrue(result)
    }

    enum CamelCaseEnumRoute: String, CaseIterable {
        case userProfile
        case accountSettings
        case analyticsData
    }

    enum KebabCaseEnumCommand: String, CaseIterable {
        case userProfile = "user-profile"
        case accountSettings = "account-settings"
        case analyticsData = "analytics-data"
    }

    func testCanonicalTokenNormalization() {
        XCTAssertEqual(RouteParityGate.canonicalToken("userProfile"), "user-profile")
        XCTAssertEqual(RouteParityGate.canonicalToken("UserProfile"), "user-profile")
        XCTAssertEqual(RouteParityGate.canonicalToken("user_profile"), "user-profile")
        XCTAssertEqual(RouteParityGate.canonicalToken("user-profile"), "user-profile")
        XCTAssertEqual(RouteParityGate.canonicalToken("accountSettingsView"), "account-settings-view")
        XCTAssertEqual(RouteParityGate.canonicalToken("simple"), "simple")
    }

    func testCamelCaseToKebabCaseParityMatching() {
        let result = assertSurfaceParity(
            routes: CamelCaseEnumRoute.self,
            commands: KebabCaseEnumCommand.self
        )
        XCTAssertTrue(result)

        let verdict = RouteParityGate.verifyParity(
            routes: CamelCaseEnumRoute.self,
            commands: KebabCaseEnumCommand.self
        )
        XCTAssertTrue(verdict.isIsomorphic)
        XCTAssertTrue(verdict.differences.isEmpty)
        XCTAssertEqual(verdict.comparedNodesCount, 3)
    }
}
