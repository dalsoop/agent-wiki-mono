import Foundation

public struct DatabaseViewerState: Codable, Equatable, Sendable {
    public var selectedTargetID: String?
    public var selectedWorkbenchTab: WorkbenchTab
    public var recentQueries: [String]
    public var executionHistory: [QueryExecutionRecord]
    public var settings: DatabaseViewerSettings
    public var queryTabs: [QueryTab]
    public var selectedQueryTabID: String?

    public init(
        selectedTargetID: String? = nil,
        selectedWorkbenchTab: WorkbenchTab = .query,
        recentQueries: [String] = [],
        executionHistory: [QueryExecutionRecord] = [],
        settings: DatabaseViewerSettings = DatabaseViewerSettings(),
        queryTabs: [QueryTab] = [QueryTab()],
        selectedQueryTabID: String? = nil
    ) {
        self.selectedTargetID = selectedTargetID
        self.selectedWorkbenchTab = selectedWorkbenchTab
        self.recentQueries = recentQueries
        self.executionHistory = executionHistory
        self.settings = settings
        let usableTabs = queryTabs.isEmpty ? [QueryTab()] : queryTabs
        self.queryTabs = usableTabs
        self.selectedQueryTabID = selectedQueryTabID ?? usableTabs.first?.id
    }

    private enum CodingKeys: String, CodingKey {
        case selectedTargetID
        case selectedWorkbenchTab
        case recentQueries
        case executionHistory
        case settings
        case queryTabs
        case selectedQueryTabID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let selectedTargetID = try container.decodeIfPresent(String.self, forKey: .selectedTargetID)
        let selectedWorkbenchTab = try container.decodeIfPresent(WorkbenchTab.self, forKey: .selectedWorkbenchTab) ?? .query
        let recentQueries = try container.decodeIfPresent([String].self, forKey: .recentQueries) ?? []
        let executionHistory = try container.decodeIfPresent([QueryExecutionRecord].self, forKey: .executionHistory) ?? []
        let settings = try container.decodeIfPresent(DatabaseViewerSettings.self, forKey: .settings) ?? DatabaseViewerSettings()
        let queryTabs = try container.decodeIfPresent([QueryTab].self, forKey: .queryTabs) ?? [QueryTab()]
        let selectedQueryTabID = try container.decodeIfPresent(String.self, forKey: .selectedQueryTabID)
        self.init(
            selectedTargetID: selectedTargetID,
            selectedWorkbenchTab: selectedWorkbenchTab,
            recentQueries: recentQueries,
            executionHistory: executionHistory,
            settings: settings,
            queryTabs: queryTabs,
            selectedQueryTabID: selectedQueryTabID
        )
    }
}

public struct DatabaseViewerStore: Sendable {
    public var paths: AppPaths

    public init(paths: AppPaths = .default) {
        self.paths = paths
    }

    public func load() throws -> DatabaseViewerState {
        guard FileManager.default.fileExists(atPath: paths.storeFile.path) else {
            return DatabaseViewerState()
        }
        let data = try Data(contentsOf: paths.storeFile)
        let decoder = JSONDecoder()
        return try decoder.decode(DatabaseViewerState.self, from: data)
    }

    public func save(_ state: DatabaseViewerState) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: paths.storeFile, options: [.atomic])
    }
}
