import Foundation

/// A serializable snapshot of the most recent inspector pick. The GUI app writes
/// it on every pick; the headless MCP server reads it to answer "what element is
/// the developer pointing at?". Foundation-only on purpose — no SwiftUI/AppKit
/// leaks into the MCP binary, and the two processes share exactly one JSON file.
public struct InspectorSnapshot: Codable, Sendable {
    public struct Element: Codable, Sendable {
        public var name: String
        public var kind: String
        public var selector: String
        /// `"SettingsView.swift:42"`.
        public var source: String
        /// `[x, y, w, h]` in the inspector coordinate space.
        public var frame: [Double]
        /// Runtime values the developer attached at the pick (e.g. field text).
        public var values: [String: String]

        public init(name: String, kind: String, selector: String,
                    source: String, frame: [Double], values: [String: String] = [:]) {
            self.name = name
            self.kind = kind
            self.selector = selector
            self.source = source
            self.frame = frame
            self.values = values
        }
    }

    public var element: Element
    /// Path to the marked screenshot, if one was written.
    public var screenshotPath: String?
    /// Recent app log lines captured at pick time (oldest first).
    public var logs: [String]
    /// The ready-to-paste Markdown block (same as the clipboard copy).
    public var promptContext: String
    /// Unix epoch seconds when the pick happened.
    public var timestamp: Double

    public init(element: Element, screenshotPath: String?, logs: [String],
                promptContext: String, timestamp: Double) {
        self.element = element
        self.screenshotPath = screenshotPath
        self.logs = logs
        self.promptContext = promptContext
        self.timestamp = timestamp
    }
}

/// Reads/writes the shared snapshot file. Location is stable across the app and
/// the MCP server so both see the same "last pick".
public enum InspectorStateStore {
    /// `~/Library/Application Support/InspectorKit/last-pick.json`
    public static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("InspectorKit/last-pick.json")
    }

    public static func save(_ snapshot: InspectorSnapshot) throws {
        let url = fileURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    public static func load() throws -> InspectorSnapshot {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(InspectorSnapshot.self, from: data)
    }
}
