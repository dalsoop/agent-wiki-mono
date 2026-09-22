import Foundation

struct EvaluationSignalRepoShape {
    var exists: Bool
    var tests: Bool
    var packaging: Bool
    var cliIdentity: Bool
    var license: Bool

    static func inspect(
        slug: String,
        appsRoot: URL?,
        fileManager: FileManager
    ) -> EvaluationSignalRepoShape {
        guard let appsRoot else { return missing }
        let candidates = [
            appsRoot.appending(path: slug, directoryHint: .isDirectory),
            appsRoot.appending(
                path: slug.hasSuffix("-swift") ? slug : "\(slug)-swift",
                directoryHint: .isDirectory
            ),
            appsRoot.appending(
                path: slug.replacingOccurrences(of: "-swift", with: ""),
                directoryHint: .isDirectory
            ),
        ]
        guard let dir = candidates.first(where: {
            fileManager.fileExists(atPath: $0.appending(path: "Package.swift").path)
        }) else {
            return missing
        }
        let tests = fileManager.fileExists(atPath: dir.appending(path: "Tests").path)
        let packaging = fileManager.fileExists(atPath: dir.appending(path: "Packaging").path)
        let identity =
            fileManager.fileExists(atPath: dir.appending(path: "Packaging/package-identity.json").path)
            || fileManager.fileExists(atPath: dir.appending(path: "package-identity.json").path)
        let license =
            fileManager.fileExists(atPath: dir.appending(path: "LICENSE").path)
            || fileManager.fileExists(atPath: dir.appending(path: "LICENSE.md").path)
        return EvaluationSignalRepoShape(
            exists: true,
            tests: tests,
            packaging: packaging,
            cliIdentity: identity,
            license: license
        )
    }

    private static var missing: EvaluationSignalRepoShape {
        EvaluationSignalRepoShape(
            exists: false,
            tests: false,
            packaging: false,
            cliIdentity: false,
            license: false
        )
    }
}
