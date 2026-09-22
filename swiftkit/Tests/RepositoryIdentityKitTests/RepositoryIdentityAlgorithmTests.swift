import Foundation
import Testing
@testable import RepositoryIdentityKit

@Suite("Repository identity algorithm v1")
struct RepositoryIdentityAlgorithmTests {
    @Test("SSH, SCP, and HTTPS forms keep one exact repo ID")
    func equivalentRemoteForms() throws {
        let remotes = [
            "git@GitHub.com:OpenAI/example.git",
            "ssh://git@github.com/OpenAI/example.git",
            "https://github.com/OpenAI/example.git/",
        ]
        let normalized = try remotes.map(RepositoryIdentityAlgorithm.normalize(remoteURL:))
        #expect(Set(normalized) == ["github.com/OpenAI/example"])
        let ids = Set(normalized.map(RepositoryIdentityAlgorithm.repoID(normalizedRemote:)))
        #expect(ids == ["repo-sha256-941e46ac8a2d45bed98c625ebefc4b42b164aaef292f6f024f0ee00d6f94c58d"])
        #expect(ids.allSatisfy(RepositoryIdentityAlgorithm.isCanonicalRepoID))
        #expect(RepositoryIdentityAlgorithm.version == "repository-identity.v1")
    }

    @Test("Published repository identity fixtures remain executable contract cases")
    func publishedFixtures() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("protocols/repository-identity-v1.fixtures.json")
        let root = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        #expect(root["algorithmVersion"] as? String == RepositoryIdentityAlgorithm.version)
        let fixtures = try #require(root["cases"] as? [[String: Any]])
        #expect(!fixtures.isEmpty)

        for fixture in fixtures {
            let expectedRemote = try #require(fixture["normalizedRemote"] as? String)
            let expectedRepoID = try #require(fixture["repoId"] as? String)
            let remotes = try #require(fixture["remoteForms"] as? [String])
            for remote in remotes {
                let normalized = try RepositoryIdentityAlgorithm.normalize(remoteURL: remote)
                #expect(normalized == expectedRemote)
                #expect(RepositoryIdentityAlgorithm.repoID(normalizedRemote: normalized) == expectedRepoID)
            }
            #expect(RepositoryIdentityAlgorithm.isCanonicalRepoID(expectedRepoID))
        }
    }
}
