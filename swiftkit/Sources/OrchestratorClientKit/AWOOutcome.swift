import Foundation

/// AWO CLI 호출 결과.
public struct AWOOutcome: Sendable {
    public let ok: Bool
    public let message: String
    public let exitCode: Int32
    public let jobID: String?

    public init(ok: Bool, message: String, exitCode: Int32 = 0, jobID: String? = nil) {
        self.ok = ok
        self.message = message
        self.exitCode = exitCode
        self.jobID = jobID
    }

    /// `dispatch --json` 출력에서 잡 id를 꺼낸다. `{id}` · `{job:{id}}` · `{result:{id}}` 모두 받는다.
    public static func parseJobID(from output: String) -> String? {
        guard let data = output.data(using: .utf8),
              let obj = OrchestratorJSON.object(from: data)
        else { return nil }
        if let id = obj["id"] as? String { return id }
        if let job = obj["job"] as? [String: Any], let id = job["id"] as? String { return id }
        if let result = obj["result"] as? [String: Any], let id = result["id"] as? String { return id }
        if let result = obj["result"] as? String { return result }
        return nil
    }
}

/// AWO 잡 요약 — `jobs --json` 출력의 경량 파싱.
public struct AWOJobSummary: Codable, Sendable, Identifiable {
    public let id: String
    public var state: String
    public var spec: Spec

    public struct Spec: Codable, Sendable {
        public var title: String
        public var worker: String
        public var model: String?
        public var tenantID: String?
        public var backlogIDs: [String]?

        private enum CodingKeys: String, CodingKey {
            case title, worker, model, tenantID, backlogIDs
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decode(String.self, forKey: .title)
            worker = try c.decodeIfPresent(String.self, forKey: .worker) ?? "codex"
            model = try c.decodeIfPresent(String.self, forKey: .model)
            tenantID = try c.decodeIfPresent(String.self, forKey: .tenantID)
            backlogIDs = try c.decodeIfPresent([String].self, forKey: .backlogIDs)
        }
    }
}
