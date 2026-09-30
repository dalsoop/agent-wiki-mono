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

        /// 기본 원격은 없다. 옛 내부 GitLab(10.0.50.63)은 2026-09-24 퇴역했고, gitlab.com 에는 이 저장소가 없다.
        /// 원격을 쓰려면 endpoints.json(`.gitlab-status-ui/`)에 endpoint 를 적는다.
        public static let `default` = Catalog(endpoints: [])

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

    /// 지금 clone 할 주소. 설정된 endpoint 가 없으면 nil — 옛 호스트로 폴백하지 않는다.
    public static func current() -> String? {
        let sorted = Catalog.load().endpoints.sorted { $0.priority < $1.priority }
        return sorted.first?.gitRemote(project: project)
    }

    /// 원격이 없을 때 clone 안내 대신 보여 주는 문구.
    public static let unconfiguredHint =
        "원격 git 저장소가 설정돼 있지 않다 — endpoints.json(.gitlab-status-ui/)에 endpoint 를 적거나 피어 Mac 에서 가져온다"

    /// CLI 의 clone 안내 한 줄.
    public static var cloneHint: String {
        current().map { "  → clone: git clone \($0) ~/gujo-wiki" } ?? "  → \(unconfiguredHint)"
    }
}
