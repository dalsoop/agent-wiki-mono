import Foundation
import StateRootKit

enum TenantAuditLog {
    enum Action: String, Encodable {
        case allowed
        case denied
    }

    struct Entry: Encodable {
        let timestamp: String
        let cli: String
        let tenantID: String?
        let agentID: String?
        let action: Action
        let reason: String
    }

    static func record(
        tenantSlug: String?,
        tenantID: String?,
        agentID: String?,
        action: Action,
        reason: String,
        homeDirectory: String? = nil
    ) {
        let cli = (CommandLine.arguments.first ?? "unknown")
            .split(separator: "/").last.map(String.init) ?? "unknown"

        let entry = Entry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            cli: cli,
            tenantID: tenantID,
            agentID: agentID,
            action: action,
            reason: reason
        )

        guard let jsonData = try? JSONEncoder().encode(entry) else { return }
        var line = jsonData
        line.append(contentsOf: [0x0A]) // newline

        let path: String
        if let slug = tenantSlug, !slug.isEmpty {
            path = StateRootKit.path(".tenants/\(slug)/audit.jsonl", homeDirectory: homeDirectory)
        } else {
            path = StateRootKit.hostPath(".agent-tenant-isolation-manager/audit-denied.jsonl", homeDirectory: homeDirectory)
        }

        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        do { try fm.createDirectory(atPath: dir, withIntermediateDirectories: true) } catch { _ = error }

        if fm.fileExists(atPath: path) {
            guard let fh = FileHandle(forWritingAtPath: path) else { return }
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(line)
        } else {
            fm.createFile(atPath: path, contents: line)
        }
    }
}
