import Foundation

/// Cross-app operable procedure — not an agent JobSpec and not a GPU workload.
///
/// A step is one owner-app CLI invocation. There is no hub daemon: the owner
/// app ships the object in `capabilities.procedures`, and other apps read the
/// registry. Mutations still require `--dry-run` or `--confirm` at the CLI.
public struct Procedure: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    /// `Capabilities.name` of the app that owns the screen for this procedure.
    public var owner: String
    public var steps: [Step]

    public init(id: String, title: String, summary: String, owner: String, steps: [Step]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.owner = owner
        self.steps = steps
    }

    public struct Step: Codable, Equatable, Sendable, Identifiable {
        public var id: String
        public var title: String
        /// `Capabilities.name` of the app that runs this step.
        public var app: String
        public var argv: [String]
        /// True when the CLI mutation contract (`--dry-run|--confirm`) applies.
        public var mutation: Bool
        public var json: Bool

        public init(
            id: String,
            title: String,
            app: String,
            argv: [String],
            mutation: Bool = false,
            json: Bool = true
        ) {
            self.id = id
            self.title = title
            self.app = app
            self.argv = argv
            self.mutation = mutation
            self.json = json
        }

        public var commandLine: String {
            ([app] + argv).joined(separator: " ")
        }
    }
}
