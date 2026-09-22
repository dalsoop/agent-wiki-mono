import Foundation

public enum RepositoryAgentRoleStoreError: Error, CustomStringConvertible, Equatable {
    case invalidRoleID(String)
    case missingRole(String)
    case emptyDefinition

    public var description: String {
        switch self {
        case .invalidRoleID(let id): "역할 ID는 kebab-case여야 합니다: \(id)"
        case .missingRole(let id): "저장소 역할을 찾을 수 없습니다: \(id)"
        case .emptyDefinition: "역할 정의가 비어 있습니다"
        }
    }
}

public struct RepositoryAgentRole: Identifiable, Sendable, Equatable {
    public static let supportedEngines = ["claude", "codex", "grok", "opencode"]

    public let id: String
    public let displayName: String
    public let summary: String
    public let engine: String
    public let mode: String
    public let definition: String
    public let fileURL: URL

    public init(
        id: String,
        displayName: String,
        summary: String,
        engine: String,
        mode: String,
        definition: String,
        fileURL: URL
    ) {
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.engine = engine
        self.mode = mode
        self.definition = definition
        self.fileURL = fileURL
    }
}

/// 저장소 담당 역할의 엔진 중립 기계 SSOT: `<repo>/.agents/roles/<id>.md`.
public struct RepositoryAgentRoleStore: Sendable {
    public let repositoryRoot: URL

    public init(repositoryRoot: URL) {
        self.repositoryRoot = repositoryRoot.standardizedFileURL
    }

    public static func repositoryRoot(forWorldRoot worldRoot: URL) -> URL {
        worldRoot.lastPathComponent == ".wiki"
            ? worldRoot.deletingLastPathComponent().standardizedFileURL
            : worldRoot.standardizedFileURL
    }

    public var rolesDirectory: URL {
        repositoryRoot.appendingPathComponent(".agents/roles", isDirectory: true)
    }

    public func list() -> [RepositoryAgentRole] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: rolesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        else { return [] }
        return urls
            .filter { $0.pathExtension == "md" }
            .compactMap { try? load(id: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.id < $1.id }
    }

    public func load(id: String) throws -> RepositoryAgentRole {
        try Self.validate(id: id)
        let url = rolesDirectory.appendingPathComponent("\(id).md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw RepositoryAgentRoleStoreError.missingRole(id)
        }
        return parse(id: id, text: text, url: url)
    }

    @discardableResult
    public func save(id: String, definition: String) throws -> RepositoryAgentRole {
        try Self.validate(id: id)
        let clean = definition.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw RepositoryAgentRoleStoreError.emptyDefinition }
        try FileManager.default.createDirectory(at: rolesDirectory, withIntermediateDirectories: true)
        let url = rolesDirectory.appendingPathComponent("\(id).md")
        try Data((clean + "\n").utf8).write(to: url, options: .atomic)
        return parse(id: id, text: clean, url: url)
    }

    public func makeDefinition(
        id: String,
        displayName: String,
        summary: String,
        engine: String,
        responsibilities: String
    ) throws -> String {
        try Self.validate(id: id)
        let selectedEngine = RepositoryAgentRole.supportedEngines.contains(engine) ? engine : "codex"
        return """
        ---
        name: \(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? id : displayName)
        description: \(summary.trimmingCharacters(in: .whitespacesAndNewlines))
        engine: \(selectedEngine)
        mode: on-demand
        ---

        # 담당 범위

        \(responsibilities.trimmingCharacters(in: .whitespacesAndNewlines))

        # 작업 규칙

        - 저장소 루트의 AGENTS.md를 먼저 읽고 준수한다.
        - Agent Wiki의 canonical task와 dispatch 범위 안에서만 작업한다.
        - 구현 결과를 보고하되 checker 검증 전에는 완료 처리하지 않는다.
        - 재사용 가능한 교훈은 저장소 노하우 후보로 제안한다.
        """
    }

    public static func validate(id: String) throws {
        let pattern = #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#
        guard id.range(of: pattern, options: .regularExpression) != nil else {
            throw RepositoryAgentRoleStoreError.invalidRoleID(id)
        }
    }

    private func parse(id: String, text: String, url: URL) -> RepositoryAgentRole {
        var displayName = id
        var summary = ""
        var engine = "codex"
        var mode = "on-demand"
        for line in text.split(separator: "\n").prefix(16) {
            let row = String(line)
            if row.hasPrefix("name:") {
                displayName = String(row.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if row.hasPrefix("description:") {
                summary = String(row.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            } else if row.hasPrefix("engine:") {
                let candidate = String(row.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                engine = RepositoryAgentRole.supportedEngines.contains(candidate) ? candidate : "codex"
            } else if row.hasPrefix("mode:") {
                mode = String(row.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
        }
        return RepositoryAgentRole(
            id: id,
            displayName: displayName,
            summary: summary,
            engine: engine,
            mode: mode,
            definition: text,
            fileURL: url)
    }
}
