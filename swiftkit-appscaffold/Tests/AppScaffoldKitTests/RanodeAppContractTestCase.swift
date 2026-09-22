import Foundation
import SwiftUI
import XCTest
import AppPathsKit
import StateMirrorKit
@testable import AppScaffoldKit

public protocol RanodeAppContractTestCase: AnyObject {}

extension RanodeAppContractTestCase where Self: XCTestCase {
    @MainActor
    public func assertRanodeAppContract<A: FleetManagedApp>(
        for appType: A.Type,
        slug: String,
        sqliteFile: URL? = nil,
        stateDirectory: (([String: String]) -> URL)? = nil,
        expectedDirName: String? = nil,
        stateFile: ((String, [String: String]) -> URL)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (isValid, reasons) = RanodeAppFormContract.verifyFormDefaults(for: appType)
        XCTAssertTrue(isValid, "RanodeApp form defaults invalid: \(reasons.joined(separator: ", "))", file: file, line: line)
        XCTAssertEqual(A.windowID, "main", "windowID must be 'main'", file: file, line: line)
        XCTAssertFalse(A.productName.isEmpty, "productName must not be empty", file: file, line: line)
        XCTAssertEqual(A.windowTitle, A.productName, "windowTitle must match productName", file: file, line: line)
        XCTAssertFalse(A.service.isEmpty, "service must not be empty", file: file, line: line)
        XCTAssertTrue(StateMirrorContract.verifyStateMirrorPath(slug: slug), "StateMirror path contract must be satisfied", file: file, line: line)
        if let sqliteFile {
            let ok = AppPathsContract.verifyDurableSqlitePath(
                sqliteFile: sqliteFile,
                expectedBundleID: "net.ranode.\(slug)"
            )
            XCTAssertTrue(ok, "Durable SQLite path must conform", file: file, line: line)
        }
        if let stateDirectory, let expectedDirName, let stateFile {
            let ok = AppPathsContract.verifyStateRootOverride(
                stateDirectory: stateDirectory,
                expectedDirName: expectedDirName,
                stateFile: stateFile
            )
            XCTAssertTrue(ok, "StateRoot override must conform", file: file, line: line)
        }
    }

    @MainActor
    public func assertRanodeMenuBarAppContract<A: FleetManagedMenuBarApp>(
        for appType: A.Type,
        slug: String,
        sqliteFile: URL? = nil,
        stateDirectory: (([String: String]) -> URL)? = nil,
        expectedDirName: String? = nil,
        stateFile: ((String, [String: String]) -> URL)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (isValid, reasons) = RanodeAppFormContract.verifyMenuBarFormDefaults(for: appType)
        XCTAssertTrue(isValid, "RanodeMenuBarApp form defaults invalid: \(reasons.joined(separator: ", "))", file: file, line: line)
        XCTAssertEqual(A.windowID, "main", "windowID must be 'main'", file: file, line: line)
        XCTAssertFalse(A.productName.isEmpty, "productName must not be empty", file: file, line: line)
        XCTAssertEqual(A.windowTitle, A.productName, "windowTitle must match productName", file: file, line: line)
        XCTAssertFalse(A.service.isEmpty, "service must not be empty", file: file, line: line)
        XCTAssertTrue(StateMirrorContract.verifyStateMirrorPath(slug: slug), "StateMirror path contract must be satisfied", file: file, line: line)
        if let sqliteFile {
            let ok = AppPathsContract.verifyDurableSqlitePath(
                sqliteFile: sqliteFile,
                expectedBundleID: "net.ranode.\(slug)"
            )
            XCTAssertTrue(ok, "Durable SQLite path must conform", file: file, line: line)
        }
        if let stateDirectory, let expectedDirName, let stateFile {
            let ok = AppPathsContract.verifyStateRootOverride(
                stateDirectory: stateDirectory,
                expectedDirName: expectedDirName,
                stateFile: stateFile
            )
            XCTAssertTrue(ok, "StateRoot override must conform", file: file, line: line)
        }
    }

    public func assertRanodeContract(
        windowID: String = "main",
        productName: String,
        windowTitle: String? = nil,
        service: String,
        slug: String,
        sqliteFile: URL? = nil,
        stateDirectory: (([String: String]) -> URL)? = nil,
        expectedDirName: String? = nil,
        stateFile: ((String, [String: String]) -> URL)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(windowID, "main", "windowID must be 'main'", file: file, line: line)
        XCTAssertFalse(productName.isEmpty, "productName must not be empty", file: file, line: line)
        let effectiveTitle = windowTitle ?? productName
        XCTAssertEqual(effectiveTitle, productName, "windowTitle default must match productName", file: file, line: line)
        XCTAssertFalse(service.isEmpty, "service must not be empty", file: file, line: line)
        XCTAssertTrue(StateMirrorContract.verifyStateMirrorPath(slug: slug), "StateMirror path contract must be satisfied", file: file, line: line)
        if let sqliteFile {
            let ok = AppPathsContract.verifyDurableSqlitePath(
                sqliteFile: sqliteFile,
                expectedBundleID: "net.ranode.\(slug)"
            )
            XCTAssertTrue(ok, "Durable SQLite path must conform", file: file, line: line)
        }
        if let stateDirectory, let expectedDirName, let stateFile {
            let ok = AppPathsContract.verifyStateRootOverride(
                stateDirectory: stateDirectory,
                expectedDirName: expectedDirName,
                stateFile: stateFile
            )
            XCTAssertTrue(ok, "StateRoot override must conform", file: file, line: line)
        }
    }
}
