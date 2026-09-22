import Foundation
import StateRootKit

/// 에이전트별 관제 프로필 — 원장 객체가 아니라 `~/.memo-citation-ledger/agents/<id>.json`.
/// world/domain 가중치와 pull 예산을 담는다.
public struct AgentProfile: Codable, Sendable, Equatable {
    public var id: String
    public var worlds: [String: Double]
    public var domains: [String: Double]
    public var pull: PullPolicy

    public struct PullPolicy: Codable, Sendable, Equatable {
        public var maxObjects: Int
        public var includeBlobs: Bool
        public var eventDepth: String
        public var bodyChars: Int

        public init(
            maxObjects: Int = 20,
            includeBlobs: Bool = false,
            eventDepth: String = "run",
            bodyChars: Int = 400
        ) {
            self.maxObjects = maxObjects
            self.includeBlobs = includeBlobs
            self.eventDepth = eventDepth
            self.bodyChars = bodyChars
        }
    }

    public init(
        id: String,
        worlds: [String: Double] = [:],
        domains: [String: Double] = [:],
        pull: PullPolicy = PullPolicy()
    ) {
        self.id = id
        self.worlds = worlds
        self.domains = domains
        self.pull = pull
    }

    /// profile 없음 → 빈 weights (ranker 가 fleet default 사용).
    public static func missing(id: String) -> AgentProfile {
        AgentProfile(id: id)
    }
}

public enum AgentProfileStoreError: Error, CustomStringConvertible, Equatable {
    case io(String)
    case invalidJSON(String)

    public var description: String {
        switch self {
        case .io(let s): return "agent profile io: \(s)"
        case .invalidJSON(let s): return "agent profile invalid json: \(s)"
        }
    }
}

public struct AgentProfileStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
    }

    public static var defaultDirectory: URL {
        URL(fileURLWithPath: StateRootKit.hostPath(".memo-citation-ledger/agents"))
    }

    public func fileURL(for agentID: String) -> URL {
        let safe = agentID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return directory.appendingPathComponent("\(safe).json")
    }

    public func load(id: String) throws -> AgentProfile {
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AgentProfile.missing(id: id)
        }
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw AgentProfileStoreError.io(error.localizedDescription) }
        do {
            var p = try JSONDecoder().decode(AgentProfile.self, from: data)
            if p.id.isEmpty { p.id = id }
            return p
        } catch {
            throw AgentProfileStoreError.invalidJSON(String(describing: error))
        }
    }

    public func save(_ profile: AgentProfile) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(profile)
            try data.write(to: fileURL(for: profile.id), options: .atomic)
        } catch let e as AgentProfileStoreError {
            throw e
        } catch {
            throw AgentProfileStoreError.io(error.localizedDescription)
        }
    }

    /// world weight set; 없으면 프로필 생성.
    @discardableResult
    public func setWorldWeight(agentID: String, world: String, weight: Double) throws -> AgentProfile {
        var p = try load(id: agentID)
        p.id = agentID
        p.worlds[world] = weight
        try save(p)
        return p
    }

    @discardableResult
    public func setDomainWeight(agentID: String, domain: String, weight: Double) throws -> AgentProfile {
        var p = try load(id: agentID)
        p.id = agentID
        p.domains[domain] = weight
        try save(p)
        return p
    }
}
