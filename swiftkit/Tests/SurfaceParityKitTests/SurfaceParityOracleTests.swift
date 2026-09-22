import XCTest
import SurfaceParityKit

final class SurfaceParityOracleTests: XCTestCase {
    func testIsomorphicJSONMatching() throws {
        let cli = """
        {
            "app": "demo-app",
            "updatedAt": "2026-09-13T01:00:00Z",
            "state": {
                "count": 42,
                "status": "ready",
                "items": ["alpha", "beta"]
            }
        }
        """

        let gui = """
        {
            "app": "demo-app",
            "updatedAt": "2026-09-13T02:00:00Z",
            "state": {
                "status": "ready",
                "count": 42,
                "items": ["alpha", "beta"]
            }
        }
        """

        let verdict = try SurfaceParityOracle.diff(cliJSON: cli, guiJSON: gui)
        XCTAssertTrue(verdict.isIsomorphic)
        XCTAssertTrue(verdict.differences.isEmpty)
    }

    func testDetectValueMismatch() throws {
        let cli = """
        {
            "state": {
                "count": 42
            }
        }
        """

        let gui = """
        {
            "state": {
                "count": 99
            }
        }
        """

        let verdict = try SurfaceParityOracle.diff(cliJSON: cli, guiJSON: gui)
        XCTAssertFalse(verdict.isIsomorphic)
        XCTAssertEqual(verdict.differences.count, 1)
        XCTAssertEqual(verdict.differences.first?.kind, .valueMismatch)
    }

    func testDetectKeyDiscrepancies() throws {
        let cli = """
        {
            "state": {
                "onlyInCLI": true,
                "common": "value"
            }
        }
        """

        let gui = """
        {
            "state": {
                "onlyInGUI": "extra",
                "common": "value"
            }
        }
        """

        let verdict = try SurfaceParityOracle.diff(cliJSON: cli, guiJSON: gui)
        XCTAssertFalse(verdict.isIsomorphic)
        XCTAssertEqual(verdict.differences.count, 2)

        let kinds = Set(verdict.differences.map { $0.kind })
        XCTAssertTrue(kinds.contains(.missingKeyInGUI))
        XCTAssertTrue(kinds.contains(.missingKeyInCLI))
    }

    func testAssertIsomorphicThrowsOnMismatch() {
        let cli = "{\"state\": {\"key\": 1}}"
        let gui = "{\"state\": {\"key\": 2}}"

        XCTAssertThrowsError(try SurfaceParityOracle.assertIsomorphic(cliJSON: cli, guiJSON: gui)) { error in
            guard case ParityOracleError.isomorphismViolation(let verdict) = error else {
                XCTFail("Expected isomorphismViolation error")
                return
            }
            XCTAssertFalse(verdict.isIsomorphic)
        }
    }
}
