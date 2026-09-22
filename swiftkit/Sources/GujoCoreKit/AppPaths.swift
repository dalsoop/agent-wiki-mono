import Foundation
import AppPathsKit
import StateRootKit

/// Paths under `~/Library/Application Support/Gujo/`.
/// Sole writer: Gujo Cloud Apps (`LedgerWriteAccess.cloudApps`). Gujo.app is a retired reader.
public enum AppPaths {
    public static let productFolderName = "Gujo"
    public static let ownerSlug = "gujo-cloud-apps"

    public static var support: URL {
        StateRootKit.url("Library/Application Support")
            .appendingPathComponent(productFolderName, isDirectory: true)
    }
    public static var credentialsFile: URL { support.appendingPathComponent("credentials.env") }
    public static var ledgerFile: URL { support.appendingPathComponent("ledger.json") }
    public static var legacyLedgerFile: URL { ledgerFile }
    public static var deviceFile: URL { support.appendingPathComponent("device.json") }
    public static var foldersFile: URL { support.appendingPathComponent("folders.json") }
    public static var installationsFile: URL { support.appendingPathComponent("installations.json") }
    public static var productsDir: URL { support.appendingPathComponent("products", isDirectory: true) }
    public static var defaultInstallDir: URL {
        StateRootKit.url("Applications")
            .appendingPathComponent(productFolderName, isDirectory: true)
    }
    public static func productDir(_ id: Int) -> URL { productsDir.appendingPathComponent(String(id), isDirectory: true) }

    public static var sqliteFile: URL {
        DurableAppLayout.sqliteURL(slug: "gujo")
    }}
