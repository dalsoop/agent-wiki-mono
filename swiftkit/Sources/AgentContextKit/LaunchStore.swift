import Foundation
import CryptoKit
import AgentSessionKit
import StateRootKit

/// 세션이 **시작되는 순간** 무엇이 물렸는지를 기록하는 원장.
///
/// 이게 훅 없이 "그때 그 내용"을 아는 유일한 길이다. 소급으로는 불가능하다 —
/// Claude 는 주입본을 안 남기고, 지침 md 는 대부분 git 밖이라(`~/.claude/CLAUDE.md`,
/// `WORKSPACE/CLAUDE.md`) 과거 내용을 되살릴 방법이 없다.
///
/// 훅과 다른 점: 세션 파이프라인 **안에** 아무것도 끼우지 않는다. 래퍼는 실행 전에
/// 기록하고 곧바로 `exec` 로 자기 자신을 에이전트로 갈아치운다. 그래서 래퍼가 실패해도
/// 에이전트가 막히지 않고(기록만 건너뛴다), 터미널·TTY·시그널이 그대로 보존된다.
public struct LaunchStore: Sendable {
    /// 원장 루트. `~/.agent-session-context-ledger`.
    public let root: String
    /// 지침 **본문**을 보관할 것인가.
    ///
    /// 기본은 **false** — 해시와 크기만 남긴다. 이 앱은 남의 맥에서도 도는 제품이고,
    /// 지침 md 에는 회사 규정·고객명·때로 자격증명이 들어 있다. 그걸 앱이 조용히
    /// 통째로 복제해 두는 것은 관측 도구가 할 일이 아니다.
    ///
    /// 켜면 시점 내용까지 복원되어 드리프트 대조가 가능해진다. 그 대가를 아는 사람만
    /// 켜야 하므로 기본값이 아니다.
    public let storeContent: Bool

    /// 본문 보관 opt-in 환경변수. 설정을 앱 밖에서도 켤 수 있게 한다.
    public static let contentOptInEnv = "AGENT_CONTEXT_STORE_CONTENT"

    public init(root: String = StateRootKit.path(".agent-session-context-ledger"),
                storeContent: Bool? = nil) {
        self.root = root
        self.storeContent = storeContent
            ?? (ProcessInfo.processInfo.environment[LaunchStore.contentOptInEnv].map {
                ["1", "true", "yes"].contains($0.lowercased())
            } ?? false)
    }

    var launchesDir: String { root + "/launches" }
    var blobsDir: String { root + "/blobs" }

    /// 실행 시점 스냅샷 1건.
    public struct Launch: Codable, Sendable, Equatable {
        public let sessionId: String
        public let tool: String
        public let cwd: String
        public let startedAt: Date
        public let docs: [Doc]
        /// 실제로 실행한 명령(기록용, 인자 그대로).
        public let argv: [String]
        /// 이 기록이 만들어질 때 **본문까지** 보관했나. 기본은 false(지문만).
        /// 옛 기록과 섞이므로 값을 기록에 남긴다 — 없으면 소비자가 blob 을 찾다 실패한다.
        public var contentStored: Bool = false

        public struct Doc: Codable, Sendable, Equatable {
            public let path: String
            public let layer: String
            public let sha256: String
            public let bytes: Int
            public let approxTokens: Int
            public let importedBy: String?

            public init(path: String, layer: String, sha256: String, bytes: Int,
                        approxTokens: Int, importedBy: String?) {
                self.path = path
                self.layer = layer
                self.sha256 = sha256
                self.bytes = bytes
                self.approxTokens = approxTokens
                self.importedBy = importedBy
            }
        }

        public var approxTokens: Int { docs.map(\.approxTokens).reduce(0, +) }

        public init(sessionId: String, tool: String, cwd: String, startedAt: Date,
                    docs: [Doc], argv: [String], contentStored: Bool = false) {
            self.sessionId = sessionId
            self.tool = tool
            self.cwd = cwd
            self.startedAt = startedAt
            self.docs = docs
            self.argv = argv
            self.contentStored = contentStored
        }
    }

    // MARK: - 쓰기

    /// 실행 시점 스택을 기록한다.
    ///
    /// 기본은 **지문만** — sha256·크기·토큰 추정. 그것만으로도 "그때와 지금이 다른가"는
    /// 답해진다(해시 비교). 본문이 필요한 건 **무엇이 어떻게 달라졌나**(diff)뿐이고,
    /// 그건 `storeContent` 를 켠 사람만 얻는다.
    ///
    /// 본문을 켜면 내용주소(sha256) blob 으로 dedupe — 같은 CLAUDE.md 로 100번 실행해도
    /// blob 은 하나다.
    @discardableResult
    public func record(
        sessionId: String, tool: AgentTool, cwd: String, argv: [String],
        docs: [InjectedDoc], fm: FileManager = .default
    ) throws -> Launch {
        try fm.createDirectory(atPath: launchesDir, withIntermediateDirectories: true)
        if storeContent { try fm.createDirectory(atPath: blobsDir, withIntermediateDirectories: true) }

        var stored: [Launch.Doc] = []
        for d in docs {
            guard let data = fm.contents(atPath: d.path) else { continue }
            let hash = Self.sha256(data)
            if storeContent {
                let blob = blobsDir + "/" + hash
                if !fm.fileExists(atPath: blob) { try data.write(to: URL(fileURLWithPath: blob)) }
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            stored.append(Launch.Doc(
                path: d.path, layer: d.layer, sha256: hash, bytes: data.count,
                approxTokens: TokenEstimate.approxTokens(text), importedBy: d.importedBy
            ))
        }

        let launch = Launch(sessionId: sessionId, tool: tool.rawValue, cwd: cwd,
                            startedAt: Date(), docs: stored, argv: argv,
                            contentStored: storeContent)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(launch).write(to: URL(fileURLWithPath: launchesDir + "/\(sessionId).json"))
        return launch
    }

    // MARK: - 읽기

    public func load(sessionId: String, fm: FileManager = .default) -> Launch? {
        let exact = launchesDir + "/\(sessionId).json"
        let path: String
        if fm.fileExists(atPath: exact) {
            path = exact
        } else {
            // 사용자는 세션 id 앞자리만 치는 경우가 많다.
            guard let names = try? fm.contentsOfDirectory(atPath: launchesDir),
                  let hit = names.first(where: { $0.hasPrefix(sessionId) && $0.hasSuffix(".json") })
            else { return nil }
            path = launchesDir + "/" + hit
        }
        guard let data = fm.contents(atPath: path) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Launch.self, from: data)
    }

    /// 저장된 시점 본문.
    public func blob(sha256: String, fm: FileManager = .default) -> String? {
        fm.contents(atPath: blobsDir + "/" + sha256).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// 실행 기록을 카드용 주입 스택으로 바꾼다.
    ///
    /// provenance 는 `reconstructed-exact` — 탐색 규칙으로 고른 파일이되 **그 시점 내용까지**
    /// 원장에 있다는 뜻이다. `injected`(로그에 원문이 남은 것)와는 여전히 구분한다.
    /// 래퍼가 본 것과 에이전트가 실제로 읽은 것이 이론상 어긋날 수 있기 때문이다.
    public func injectedDocs(_ launch: Launch) -> [InjectedDoc] {
        launch.docs.map {
            InjectedDoc(path: $0.path, layer: $0.layer, provenance: .reconstructedExact,
                        bytes: $0.bytes, approxTokens: $0.approxTokens,
                        importedBy: $0.importedBy, missing: false)
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
