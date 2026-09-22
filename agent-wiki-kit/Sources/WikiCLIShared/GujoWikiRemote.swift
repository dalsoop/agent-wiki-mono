import Foundation
import StateRootKit

/// 공유 3인칭 원장 clone 주소 — endpoints.json 설정 또는 기본 SSH/HTTPS 경로 해석.
public enum GujoWikiRemote {
    public static let project = "workspace/contents/gujo-wiki"

    public struct Endpoint: Codable, Sendable {
        public var host: String
        public var gitRemoteTemplate: String
        public var priority: Int

        public init(host: String, gitRemoteTemplate: String, priority: Int) {
            self.host = host
            self.gitRemoteTemplate = gitRemoteTemplate
            self.priority = priority
        }

        public func gitRemote(project: String) -> String {
            let clean = project.trimmingCharacters(in: CharacterSet(charactersIn: "/ \t\n"))
            return gitRemoteTemplate.replacingOccurrences(of: "{project}", with: clean)
        }
    }

    public struct Catalog: Codable, Sendable {
        public var endpoints: [Endpoint]

        public init(endpoints: [Endpoint]) {
            self.endpoints = endpoints
        }

        public static let `default` = Catalog(endpoints: [
            Endpoint(host: "gitlab-ssh.internal.kr", gitRemoteTemplate: "git@gitlab-ssh.internal.kr:{project}.git", priority: 10),
            Endpoint(host: "gitlab.ranode.net", gitRemoteTemplate: "https://gitlab.ranode.net/{project}.git", priority: 20)
        ])

        public static func load() -> Catalog {
            let configURL = StateRootKit.url(".gitlab-status-ui/endpoints.json")
            guard let data = try? Data(contentsOf: configURL) else {
                return .default
            }
            do {
                return try JSONDecoder().decode(Catalog.self, from: data)
            } catch {
                return .default
            }
        }
    }

    public static func current() -> String {
        let catalog = Catalog.load()
        let sorted = catalog.endpoints.sorted { $0.priority < $1.priority }
        return sorted.first?.gitRemote(project: project) ?? "https://gitlab.ranode.net/\(project).git"
    }
}
