import Foundation

public struct HarvestFile: Codable, Sendable, Equatable {
    public var fileName: String
    public var path: String
    public var bytes: Int

    public init(fileName: String, path: String, bytes: Int) {
        self.fileName = fileName
        self.path = path
        self.bytes = bytes
    }
}

public struct HarvestItem: Codable, Sendable, Equatable {
    public var programID: String
    public var files: [HarvestFile]
    public var skipped: [String]
    public var error: String?

    public init(programID: String, files: [HarvestFile], skipped: [String], error: String? = nil) {
        self.programID = programID
        self.files = files
        self.skipped = skipped
        self.error = error
    }
}

public struct HarvestManifest: Codable, Sendable, Equatable {
    public var items: [HarvestItem]
    public init(items: [HarvestItem] = []) {
        self.items = items
    }
}

public struct HarvestProgress: Codable, Sendable, Equatable {
    public var visited: [String]
    public var downloadedFiles: Int
    public var stoppedReason: String?

    public init(visited: [String] = [], downloadedFiles: Int = 0, stoppedReason: String? = nil) {
        self.visited = visited
        self.downloadedFiles = downloadedFiles
        self.stoppedReason = stoppedReason
    }
}

public struct HarvestReport: Codable, Sendable, Equatable {
    public var visited: Int
    public var remaining: Int
    public var downloadedFiles: Int
    public var programsWithHwp: Int
    public var stoppedReason: String?
    public var note: String

    public init(
        visited: Int,
        remaining: Int,
        downloadedFiles: Int,
        programsWithHwp: Int,
        stoppedReason: String? = nil,
        note: String
    ) {
        self.visited = visited
        self.remaining = remaining
        self.downloadedFiles = downloadedFiles
        self.programsWithHwp = programsWithHwp
        self.stoppedReason = stoppedReason
        self.note = note
    }
}
