import Foundation

/// PhotoOriginLedger settings.json 의 shareRoot.
public enum LedgerShareRoot: Sendable {
    public static var settingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/PhotoOriginLedger/settings.json")
    }

    public static func read() -> String? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let root = obj["shareRoot"] as? String,
                  !root.isEmpty else {
                return nil
            }
            return root
        } catch {
            return nil
        }
    }

    public static func isMounted(_ shareRoot: String? = read()) -> Bool {
        guard let shareRoot else { return false }
        return FileManager.default.fileExists(atPath: shareRoot)
    }

    public static func fileURL(shareRoot: String, rel: String) -> URL {
        URL(fileURLWithPath: shareRoot, isDirectory: true).appendingPathComponent(rel)
    }
}
