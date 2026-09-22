// Ported from mq-dir (https://github.com/h5nam/mq-dir) — MIT.
// See swiftkit/Sources/FileBrowserKit/NOTICE.md for the upstream copyright.

import Foundation

public struct FileEntry: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    public let modificationDate: Date?
    public let kind: String
    public let isHidden: Bool
    /// Finder tags attached to this URL (`URLResourceKey.tagNamesKey`).
    /// Localised to the user's system language — "Red" vs "빨강" for
    /// the same colour tag — which is why the dot rendering keys off
    /// `labelNumber` instead of matching tag-name strings.
    public let tagNames: [String]
    /// Finder colour-label index (`URLResourceKey.labelNumberKey`).
    /// `0` means "no label", `1...7` map to gray/green/purple/blue/
    /// yellow/red/orange in macOS's Finder palette. Only the most
    /// recent system label survives in this field — multi-tag rows
    /// drop their non-primary labels here but still carry the
    /// per-name tags in `tagNames`.
    public let labelNumber: Int
    /// Per-tag colour indices aligned with `tagNames` — `tagColors[i]`
    /// is the Finder colour of `tagNames[i]`. macOS stores these as
    /// "Name\n<0-7>" entries inside the
    /// `com.apple.metadata:_kMDItemUserTags` xattr; this field is the
    /// parsed projection. `0` here means "no colour", same convention
    /// as `labelNumber`. When the array is empty the row carries no
    /// tags at all; when it has the same count as `tagNames` the
    /// dot-renderer paints one swatch per entry.
    public let tagColors: [Int]
    /// True when a folder carries a custom icon set via Finder's
    /// Get Info → drag image flow (which writes an `Icon\r` file
    /// inside the folder). The row icon view swaps the SF Symbol for
    /// `NSWorkspace.shared.icon(forFile:)` when this is set so the
    /// user's chosen image actually appears. Always `false` for
    /// non-directory entries — file custom icons live in the resource
    /// fork and aren't covered yet.
    public let hasCustomIcon: Bool

    public struct FinderMeta: Hashable, Sendable {
        public var tagNames: [String]
        public var labelNumber: Int
        public var tagColors: [Int]
        public var hasCustomIcon: Bool
        public init(
            tagNames: [String] = [],
            labelNumber: Int = 0,
            tagColors: [Int] = [],
            hasCustomIcon: Bool = false
        ) {
            self.tagNames = tagNames
            self.labelNumber = labelNumber
            self.tagColors = tagColors
            self.hasCustomIcon = hasCustomIcon
        }
    }

    public init(
        url: URL,
        name: String,
        isDirectory: Bool,
        size: Int64?,
        modificationDate: Date?,
        kind: String,
        isHidden: Bool,
        finder: FinderMeta = FinderMeta()
    ) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
        self.kind = kind
        self.isHidden = isHidden
        self.tagNames = finder.tagNames
        self.labelNumber = finder.labelNumber
        self.tagColors = finder.tagColors
        self.hasCustomIcon = finder.hasCustomIcon
    }

    // URL-based id avoids collisions on case-insensitive APFS volumes where
    // `url.path` would normalize "Foo.txt" and "foo.txt" to the same string.
    public var id: URL { url }

    /// Folders-first ordering for tree-view levels: directories keep their
    /// incoming relative order, then files keep theirs. The single source of
    /// truth for "folders first, then files" — both `TreeFileListView` (per
    /// rendered level) and `FolderBrowserViewModel` (the DFS flatten that
    /// powers arrow-key nav) route through here so the two can never drift.
    /// A stable partition, not a re-sort: the caller has already applied the
    /// active sort key, so this only lifts directories above files.
    public static func treeOrdered(_ entries: [FileEntry]) -> [FileEntry] {
        let folders = entries.filter { $0.isDirectory }
        let files = entries.filter { !$0.isDirectory }
        return folders + files
    }
}

public enum FileEntrySortKey: String, CaseIterable, Codable, Sendable {
    case name
    case modified
    case size
    case kind
}

public enum FileEntrySorter {
    public static func sorted(
        _ entries: [FileEntry],
        by key: FileEntrySortKey,
        ascending: Bool,
        foldersOnTop: Bool = true
    ) -> [FileEntry] {
        entries.sorted { lhs, rhs in
            if foldersOnTop, lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }

            let comparison: ComparisonResult = switch key {
            case .name:
                lhs.name.localizedStandardCompare(rhs.name)
            case .modified:
                compareOptional(lhs.modificationDate, rhs.modificationDate)
            case .size:
                compareOptional(lhs.size, rhs.size)
            case .kind:
                lhs.kind.localizedStandardCompare(rhs.kind)
            }

            if comparison == .orderedSame {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    private static func compareOptional<T: Comparable>(_ lhs: T?, _ rhs: T?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs < rhs { return .orderedAscending }
            if lhs > rhs { return .orderedDescending }
            return .orderedSame
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }
}

