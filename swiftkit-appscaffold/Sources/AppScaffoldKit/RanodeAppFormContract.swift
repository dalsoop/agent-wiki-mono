import Foundation
import SwiftUI
import AppPathsKit
import StateMirrorKit

public enum RanodeAppFormContract {
    @MainActor
    public static func verifyFormDefaults<A: FleetManagedApp>(for appType: A.Type) -> (isValid: Bool, reasons: [String]) {
        let checks: [(Bool, String)] = [
            (appType.windowID != "main", "windowID must be 'main', got '\(appType.windowID)'"),
            (appType.windowTitle != appType.productName, "windowTitle default must match productName '\(appType.productName)', got '\(appType.windowTitle)'"),
            (appType.service.isEmpty, "service identifier must not be empty"),
            (appType.productName.isEmpty, "productName must not be empty")
        ]
        let reasons = checks.compactMap { $0.0 ? $0.1 : nil }
        return (reasons.isEmpty, reasons)
    }

    @MainActor
    public static func verifyMenuBarFormDefaults<A: FleetManagedMenuBarApp>(for appType: A.Type) -> (isValid: Bool, reasons: [String]) {
        let checks: [(Bool, String)] = [
            (appType.windowID != "main", "windowID must be 'main', got '\(appType.windowID)'"),
            (appType.windowTitle != appType.productName, "windowTitle default must match productName '\(appType.productName)', got '\(appType.windowTitle)'"),
            (appType.service.isEmpty, "service identifier must not be empty"),
            (appType.productName.isEmpty, "productName must not be empty")
        ]
        let reasons = checks.compactMap { $0.0 ? $0.1 : nil }
        return (reasons.isEmpty, reasons)
    }

    @discardableResult
    public static func assertConforms(
        slug: String,
        sqliteFile: URL? = nil,
        stateDirectory: (([String: String]) -> URL)? = nil,
        expectedDirName: String? = nil,
        stateFile: ((String, [String: String]) -> URL)? = nil
    ) -> Bool {
        guard !slug.isEmpty else { return false }
        guard StateMirrorContract.verifyStateMirrorPath(slug: slug) else { return false }
        if let sqlite = sqliteFile {
            guard AppPathsContract.verifyDurableSqlitePath(sqliteFile: sqlite, expectedBundleID: "net.ranode.\(slug)") else {
                return false
            }
        }
        if let stateDir = stateDirectory, let dirName = expectedDirName, let sFile = stateFile {
            guard AppPathsContract.verifyStateRootOverride(
                stateDirectory: stateDir,
                expectedDirName: dirName,
                stateFile: sFile
            ) else {
                return false
            }
        }
        return true
    }

    @discardableResult
    @MainActor
    public static func assertConforms<A: FleetManagedApp>(
        appType: A.Type,
        slug: String,
        sqliteFile: URL? = nil,
        stateDirectory: (([String: String]) -> URL)? = nil,
        expectedDirName: String? = nil,
        stateFile: ((String, [String: String]) -> URL)? = nil
    ) -> Bool {
        let (isValid, _) = verifyFormDefaults(for: appType)
        guard isValid else { return false }
        return assertConforms(
            slug: slug,
            sqliteFile: sqliteFile,
            stateDirectory: stateDirectory,
            expectedDirName: expectedDirName,
            stateFile: stateFile
        )
    }

    @discardableResult
    @MainActor
    public static func assertConforms<A: FleetManagedMenuBarApp>(
        menuBarAppType: A.Type,
        slug: String,
        sqliteFile: URL? = nil,
        stateDirectory: (([String: String]) -> URL)? = nil,
        expectedDirName: String? = nil,
        stateFile: ((String, [String: String]) -> URL)? = nil
    ) -> Bool {
        let (isValid, _) = verifyMenuBarFormDefaults(for: menuBarAppType)
        guard isValid else { return false }
        return assertConforms(
            slug: slug,
            sqliteFile: sqliteFile,
            stateDirectory: stateDirectory,
            expectedDirName: expectedDirName,
            stateFile: stateFile
        )
    }
}

public enum AppPathsContract {
    public static func verifyDurableSqlitePath(sqliteFile: URL, expectedBundleID: String) -> Bool {
        guard sqliteFile.lastPathComponent == "app.sqlite" else { return false }
        guard sqliteFile.path.contains(expectedBundleID) else { return false }
        guard let canonical = try? SafePathCanonicalizer.canonicalPath(for: sqliteFile) else { return false }
        guard canonical.lastPathComponent == "app.sqlite" else { return false }
        guard canonical.path.contains(expectedBundleID) else { return false }
        return true
    }

    public static func verifyStateRootOverride(
        stateDirectory: ([String: String]) -> URL,
        expectedDirName: String,
        stateFile: (String, [String: String]) -> URL
    ) -> Bool {
        let uniqueID = UUID().uuidString
        let mockRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-root-\(uniqueID)", isDirectory: true)
        let env = ["SWIFT_APP_STATE_ROOT": mockRoot.path]

        let dir = stateDirectory(env)
        guard dir.lastPathComponent == expectedDirName else { return false }
        guard dir.path.hasPrefix(mockRoot.path) else { return false }
        guard stateFile("test.json", env).deletingLastPathComponent().path == dir.path else { return false }
        return true
    }
}

public enum CapabilitiesCoverageContract {
    public static func verifyCapabilitiesPayload(data: Data) -> Bool {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            return false
        }
        guard let json = object as? [String: Any],
              let commands = json["commands"] as? [String: Any],
              !commands.isEmpty else {
            return false
        }
        return true
    }

    public static func verifyCapabilitiesJSONString(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        return verifyCapabilitiesPayload(data: data)
    }
}

public enum StateMirrorContract {
    public static func stateMirrorURL(for slug: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let baseDir = StateMirror.directory(environment: environment)
        return URL(fileURLWithPath: baseDir).appendingPathComponent("\(slug).json")
    }

    public static func verifyStateMirrorPath(slug: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard !slug.isEmpty else { return false }
        let dir = StateMirror.directory(environment: environment)
        guard !dir.isEmpty else { return false }
        let url = stateMirrorURL(for: slug, environment: environment)
        guard url.lastPathComponent == "\(slug).json" else { return false }
        return true
    }
}

