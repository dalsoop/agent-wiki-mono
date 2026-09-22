import Foundation

/// 코디네이터 inbox에서 pending 항목을 AWO로 자동 dispatch하는 공유 로직.
///
/// 코디네이터 3종(infra/feature/quality)이 이 타입을 쓰면 inbox→AWO 파이프라인이
/// 자동으로 연결된다. specBuilder 클로저로 각 코디네이터가 자기 도메인에 맞게
/// JobSpec을 조립한다.
public struct InboxAutoDispatcher: Sendable {
    private let client: AWOClient
    private let inboxDir: URL

    public init(client: AWOClient = AWOClient(), inboxDir: URL) {
        self.client = client
        self.inboxDir = inboxDir
    }

    /// pending inbox 항목을 찾아서 dispatch.
    ///
    /// - Parameters:
    ///   - dryRun: true면 CLI를 호출하지 않는다. 기본 false.
    ///   - specBuilder: InboxEntry를 AWOJobSpec으로 변환. nil을 반환하면 건너뜀.
    /// - Returns: dispatch 결과 목록(건너뛴 항목은 포함하지 않음).
    public func dispatchPending(
        dryRun: Bool = false,
        specBuilder: (InboxEntry) -> AWOJobSpec?
    ) async -> [(entry: InboxEntry, outcome: AWOOutcome)] {
        let entries: [InboxEntry]
        do { entries = try loadPending() }
        catch { return [] }

        var results: [(InboxEntry, AWOOutcome)] = []
        for entry in entries {
            if let handoff = entry.handoff, handoff != "none", !handoff.isEmpty {
                continue
            }
            guard let spec = specBuilder(entry) else { continue }
            if spec.workdir.isEmpty || !FileManager.default.fileExists(atPath: spec.workdir) {
                results.append((entry, AWOOutcome(
                    ok: false,
                    message: "workdir 없음: \(spec.workdir.isEmpty ? "(empty)" : spec.workdir)",
                    exitCode: 2
                )))
                continue
            }
            if dryRun {
                results.append((entry, AWOOutcome(ok: true, message: "dry-run", jobID: nil)))
                continue
            }
            let outcome = await client.dispatch(spec, queueOnly: true)
            if outcome.ok {
                markDispatched(entry)
            }
            results.append((entry, outcome))
        }
        return results
    }

    /// pending 건수만 빠르게 확인 (UI 표시용).
    public func pendingCount() -> Int {
        (try? loadPending().count) ?? 0
    }

    // MARK: - Private

    private func loadPending() throws -> [InboxEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: inboxDir.path) else { return [] }
        let files = try fm.contentsOfDirectory(at: inboxDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return files.compactMap { url -> InboxEntry? in
            guard let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder().decode(InboxEntry.self, from: data),
                  entry.status == "pending" else { return nil }
            return entry
        }
    }

    private func markDispatched(_ entry: InboxEntry) {
        let url = inboxDir.appendingPathComponent("\(entry.id).json")
        guard let data = try? Data(contentsOf: url),
              var dict = OrchestratorJSON.object(from: data) else { return }
        dict["status"] = "dispatched"
        guard let updated = OrchestratorJSON.data(withJSONObject: dict, options: [.sortedKeys, .prettyPrinted]) else { return }
        do { try updated.write(to: url) } catch { _ = error }
    }
}

/// 코디네이터 inbox 항목 — JSON 파일에서 읽는 경량 타입.
/// 각 코디네이터의 InboxItem과 JSON 계약만 맞추고 Swift 모듈 의존은 없다.
public struct InboxEntry: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let source: String
    public var status: String
    public var backlogIDs: [String]
    public var workdir: String?
    public var tenantID: String?
    /// 다른 코디네이터로 넘긴 항목. `none` 또는 nil 이면 이 인박스 소유.
    public var handoff: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, body, detail, source, status, backlogIDs, workdir, cwd, tenantID, handoff
    }

    public struct Placement: Sendable, Equatable {
        public var workdir: String?
        public var tenantID: String?
        public var handoff: String?

        public init(workdir: String? = nil, tenantID: String? = nil, handoff: String? = nil) {
            self.workdir = workdir
            self.tenantID = tenantID
            self.handoff = handoff
        }
    }

    public init(
        id: String,
        title: String,
        body: String = "",
        source: String = "",
        status: String = "pending",
        backlogIDs: [String] = [],
        placement: Placement = Placement()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.source = source
        self.status = status
        self.backlogIDs = backlogIDs
        self.workdir = placement.workdir
        self.tenantID = placement.tenantID
        self.handoff = placement.handoff
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "(제목 없음)"
        body = try c.decodeIfPresent(String.self, forKey: .body)
            ?? c.decodeIfPresent(String.self, forKey: .detail)
            ?? ""
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        backlogIDs = try c.decodeIfPresent([String].self, forKey: .backlogIDs) ?? []
        workdir = try c.decodeIfPresent(String.self, forKey: .workdir)
            ?? c.decodeIfPresent(String.self, forKey: .cwd)
        tenantID = try c.decodeIfPresent(String.self, forKey: .tenantID)
        handoff = try c.decodeIfPresent(String.self, forKey: .handoff)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(source, forKey: .source)
        try c.encode(status, forKey: .status)
        try c.encode(backlogIDs, forKey: .backlogIDs)
        try c.encodeIfPresent(workdir, forKey: .workdir)
        try c.encodeIfPresent(tenantID, forKey: .tenantID)
        try c.encodeIfPresent(handoff, forKey: .handoff)
    }
}
