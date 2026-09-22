import Foundation

public struct EvaluationStore: Sendable {
    public static var defaultRoot: URL {
        PortfolioPaths.evaluations()
    }

    public let root: URL

    public init(root: URL = Self.defaultRoot) {
        self.root = root
    }

    public func list() throws -> [EvaluationSummary] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        return try files
            .filter { $0.pathExtension == "json" }
            .map { try EvaluationSummary(evaluation: loadFile($0).current) }
            .sorted { $0.slug < $1.slug }
    }

    public func load(slug: String) throws -> EvaluationDocument {
        guard Evaluation.isValid(slug: slug) else {
            throw EvaluationError.invalidSlug(slug)
        }
        let url = fileURL(for: slug)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EvaluationError.notFound(slug)
        }
        return try loadFile(url)
    }

    public func exists(slug: String) -> Bool {
        guard Evaluation.isValid(slug: slug) else { return false }
        return FileManager.default.fileExists(atPath: fileURL(for: slug).path)
    }

    public func save(_ evaluation: Evaluation) throws {
        let previous: EvaluationDocument?
        do {
            previous = try load(slug: evaluation.slug)
        } catch {
            previous = nil
        }
        let history = previous.map { [$0.current] + $0.history } ?? []
        try write(EvaluationDocument(current: evaluation, history: history))
    }

    @discardableResult
    public func addImprovement(
        slug: String,
        text: String,
        severity: ImprovementSeverity,
        suggestedAction: String?
    ) throws -> EvaluationDocument {
        let document = try load(slug: slug)
        let improvement = try Improvement(
            text: text,
            severity: severity,
            suggestedAction: suggestedAction
        )
        let updated = EvaluationDocument(
            current: try document.current.appending(improvement: improvement),
            history: document.history
        )
        try write(updated)
        return updated
    }

    private func fileURL(for slug: String) -> URL {
        root.appending(path: "\(slug).json", directoryHint: .notDirectory)
    }

    private func loadFile(_ url: URL) throws -> EvaluationDocument {
        try EvaluationCodec.decode(Data(contentsOf: url))
    }

    private func write(_ document: EvaluationDocument) throws {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        try EvaluationCodec.encode(document).write(
            to: fileURL(for: document.current.slug),
            options: .atomic
        )
    }
}
