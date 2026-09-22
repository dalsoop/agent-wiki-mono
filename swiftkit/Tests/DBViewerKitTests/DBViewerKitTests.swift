import XCTest
@testable import DBViewerKit

final class DBViewerKitTests: XCTestCase {
    func testSQLSafetyAllowsReadOnlySingleStatement() {
        XCTAssertTrue(SQLSafety.isReadOnly("select 1"))
        XCTAssertFalse(SQLSafety.isReadOnly("select 1; drop table t"))
        XCTAssertFalse(SQLSafety.isReadOnly("delete from t"))
    }

    func testTSVParserRoundTrip() throws {
        let result = try TSVParser.parse("a\tb\n1\t2\n")
        XCTAssertEqual(result.columns, ["a", "b"])
        XCTAssertEqual(result.rows, [["1", "2"]])
    }

    func testProcessDatabaseCommandRunnerRunsEcho() async {
        let runner = ProcessDatabaseCommandRunner()
        let result = await runner.run(DatabaseCommand(executable: "/bin/echo", arguments: ["hi"]))
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.trimmedStdout, "hi")
    }

    func testLaravelClassifier() {
        XCTAssertTrue(LaravelTableClassifier.isFramework("migrations"))
        XCTAssertTrue(LaravelTableClassifier.isFramework("telescope_entries"))
        XCTAssertFalse(LaravelTableClassifier.isFramework("users"))
    }
}
