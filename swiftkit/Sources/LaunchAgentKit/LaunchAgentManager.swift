import Foundation
import CommandKit

public enum LaunchAgentManagerError: Error, LocalizedError {
    case installFailed(reason: String)
    case uninstallFailed(reason: String)
    case executableNotFound(appName: String)
    
    public var errorDescription: String? {
        switch self {
        case .installFailed(let reason):
            return "Install failed: \(reason)"
        case .uninstallFailed(let reason):
            return "Uninstall failed: \(reason)"
        case .executableNotFound(let appName):
            return "Executable not found for: \(appName)"
        }
    }
}

public class LaunchAgentManager {
    public init() {}
    
    public func resolveExecutablePath(appName: String, customCandidates: [String] = []) -> String {
        #if arch(arm64)
        let brewBin = "/opt/homebrew/bin/\(appName)"
        #else
        let brewBin = "/usr/local/bin/\(appName)"
        #endif
        let candidates = customCandidates + [
            "~/.local/bin/\(appName)".expandingTilde,
            brewBin,
            "/usr/local/bin/\(appName)"
        ]
        
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        
        // Fallback or let user handle error
        return customCandidates.first ?? "~/.local/bin/\(appName)".expandingTilde
    }
    
    public func generatePlist(config: LaunchAgentConfiguration) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(config.label)</string>
            <key>ProgramArguments</key>
            <array>

        """
        
        let args = config.caffeinate
            ? ["/usr/bin/caffeinate", "-s", config.executablePath] + config.arguments
            : [config.executablePath] + config.arguments
        
        for arg in args {
            xml += "        <string>\(escapeXML(arg))</string>\n"
        }
        xml += "    </array>\n"
        
        switch config.schedule {
        case .interval(let seconds):
            xml += """
                <key>StartInterval</key>
                <integer>\(seconds)</integer>
            
            """
        case .calendar(let hour, let minute):
            xml += """
                <key>StartCalendarInterval</key>
                <dict>
                    <key>Hour</key>
                    <integer>\(hour)</integer>
                    <key>Minute</key>
                    <integer>\(minute)</integer>
                </dict>
            
            """
        case .none:
            break
        }
        
        if let out = config.standardOutPath {
            xml += """
                <key>StandardOutPath</key>
                <string>\(escapeXML(out))</string>
            
            """
        }
        
        if let err = config.standardErrorPath {
            xml += """
                <key>StandardErrorPath</key>
                <string>\(escapeXML(err))</string>
            
            """
        }
        
        xml += """
            <key>KeepAlive</key>
            <\(config.keepAlive ? "true" : "false")/>
            <key>ProcessType</key>
            <string>\(config.processType)</string>
        </dict>
        </plist>
        """
        return xml
    }
    
    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    private func plistPath(for label: String) -> URL {
        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        return launchAgentsDir.appendingPathComponent("\(label).plist")
    }
    
    public func install(config: LaunchAgentConfiguration) throws {
        let plistURL = plistPath(for: config.label)
        
        let fm = FileManager.default
        let dir = plistURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Logs dir
        if let out = config.standardOutPath {
            let outDir = (out as NSString).deletingLastPathComponent
            if !fm.fileExists(atPath: outDir) {
                try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true, attributes: nil)
            }
        }
        
        if let err = config.standardErrorPath {
            let errDir = (err as NSString).deletingLastPathComponent
            if !fm.fileExists(atPath: errDir) {
                try fm.createDirectory(atPath: errDir, withIntermediateDirectories: true, attributes: nil)
            }
        }
        
        let plistContent = generatePlist(config: config)
        try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
        
        // plutil lint
        let lintRes = CommandKitSync.run("/usr/bin/plutil", ["-lint", plistURL.path])
        if lintRes.exitCode != 0 {
            throw LaunchAgentManagerError.installFailed(reason: "Invalid plist generated. plutil: \(lintRes.stderr.isEmpty ? lintRes.stdout : lintRes.stderr)")
        }
        
        // Unload first if exists
        _ = CommandKitSync.run("/bin/launchctl", ["bootout", "gui/\(getuid())", plistURL.path])
        
        // Load
        let loadRes = CommandKitSync.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path])
        if loadRes.exitCode != 0 {
            // fallback to load (for older macOS, though bootstrap is standard since 10.10)
            let fallbackLoadRes = CommandKitSync.run("/bin/launchctl", ["load", "-w", plistURL.path])
            if fallbackLoadRes.exitCode != 0 {
                throw LaunchAgentManagerError.installFailed(reason: "launchctl bootstrap/load failed: \(loadRes.stderr.isEmpty ? loadRes.stdout : loadRes.stderr) / \(fallbackLoadRes.stderr.isEmpty ? fallbackLoadRes.stdout : fallbackLoadRes.stderr)")
            }
        }
    }
    
    public func uninstall(label: String) throws {
        let plistURL = plistPath(for: label)
        
        // Unload
        let bootoutRes = CommandKitSync.run("/bin/launchctl", ["bootout", "gui/\(getuid())", plistURL.path])
        if bootoutRes.exitCode != 0 {
            let unloadRes = CommandKitSync.run("/bin/launchctl", ["unload", "-w", plistURL.path])
            if unloadRes.exitCode != 0 && FileManager.default.fileExists(atPath: plistURL.path) {
                // Ignore unload errors if file exists, just proceed to delete, maybe it wasn't loaded
            }
        }
        
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
    
    public func status(label: String) -> LaunchAgentStatus {
        let plistURL = plistPath(for: label)
        let isInstalled = FileManager.default.fileExists(atPath: plistURL.path)
        
        // Determine isLoaded and pid
        let res = CommandKitSync.run("/bin/launchctl", ["list", label])
        if res.exitCode != 0 {
            return LaunchAgentStatus(isInstalled: isInstalled, isLoaded: false, pid: nil)
        }
        
        // Parse launchctl list output
        // It outputs a dictionary-like structure, e.g.:
        // {
        //   "PID" = 1234;
        //   "Label" = "com.example.label";
        // ...
        // }
        
        var isLoaded = true
        var pid: Int32? = nil
        
        let lines = res.stdout.components(separatedBy: .newlines)
        for line in lines where line.contains("\"PID\"") {
            let parts = line.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            let pidString = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " ;"))
            if let p = Int32(pidString) {
                pid = p
            }
        }
        
        return LaunchAgentStatus(isInstalled: isInstalled, isLoaded: isLoaded, pid: pid)
    }
}

fileprivate extension String {
    var expandingTilde: String {
        return (self as NSString).expandingTildeInPath
    }
}
