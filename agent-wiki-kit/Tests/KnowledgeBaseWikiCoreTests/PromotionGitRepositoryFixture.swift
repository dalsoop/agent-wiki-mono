import Foundation
import KnowledgeBaseWikiCore
import CommandKit

final class PromotionGitRepositoryFixture {
    let repositoryRoot: URL
    let worldRoot: URL
    let store: LedgerStore

    init(_ label: String) throws {
        repositoryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-git-\(label)-\(UUID().uuidString)", isDirectory: true)
        worldRoot = repositoryRoot.appendingPathComponent(".wiki", isDirectory: true)
        store = LedgerStore(root: worldRoot)
        try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
        _ = try git(["init", "-b", "main"])
        _ = try git(["config", "user.name", "KBW Tests"])
        _ = try git(["config", "user.email", "kbw-tests@example.test"])
        _ = try git(["remote", "add", "origin", "git@example.test:knowledge/temporary.git"])
        try "fixture\n".write(
            to: repositoryRoot.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8)
        _ = try commitAll("initial commit")
    }

    func remove() {
        try? FileManager.default.removeItem(at: repositoryRoot)
    }

    func head() throws -> String {
        try git(["rev-parse", "HEAD"])
    }

    func commitAll(_ message: String) throws -> String {
        _ = try git(["add", "--all"])
        _ = try git(["commit", "-m", message])
        return try head()
    }

    func identity(commit: String? = nil) throws -> RepositoryIdentity {
        let inspected = try GitRepositoryInspector.inspect(cwd: repositoryRoot.path)
        guard let commit else { return inspected }
        return try RepositoryIdentity(
            remoteName: inspected.remoteName,
            remoteURL: inspected.remoteURL,
            worktreePath: inspected.worktreePath,
            gitCommonDirectory: inspected.gitCommonDirectory,
            currentBranch: inspected.currentBranch,
            defaultBranch: inspected.defaultBranch,
            sourceCommit: commit)
    }

    func objectURL(id: String) throws -> URL {
        guard let enumerator = FileManager.default.enumerator(
            at: worldRoot.appendingPathComponent("objects"),
            includingPropertiesForKeys: nil
        ) else { throw PromotionGitRepositoryFixtureError("objects directory missing") }
        for case let url as URL in enumerator where url.lastPathComponent == "\(id).md" {
            return url
        }
        throw PromotionGitRepositoryFixtureError("object file missing: \(id)")
    }

    private func git(_ arguments: [String]) throws -> String {
        let result = CommandKitSync.run(
            "/usr/bin/env",
            ["git", "-C", repositoryRoot.path] + arguments,
            timeout: 30
        )
        let text = (result.stdout + result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.ok else {
            throw PromotionGitRepositoryFixtureError(
                "git \(arguments.joined(separator: " ")): \(text)")
        }
        return text
    }
}

private struct PromotionGitRepositoryFixtureError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
