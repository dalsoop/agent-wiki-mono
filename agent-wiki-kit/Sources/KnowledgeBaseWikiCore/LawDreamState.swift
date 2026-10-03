import Foundation
import StateRootKit
import WikiLedgerKit

// 드리밍 실행 상태(이 드리밍 기기의 로컬 상태)와 R2 실행 기록의 주소·요약.
// 근거: docs/architecture.md "agent-law"(드리밍 실행 R2 `<원장 키>/runs/dream/v<yymmddhhmmss>/…`, 요약은 맨 마지막,
// 요약 없는 실행 폴더는 실패한 실행), docs/business-rules.md "드리밍"(넘는 제안은 다음 실행으로).
// 로컬 상태는 R2 실행 요약에서 다시 만들 수 있다(`LawDreamState.rebuild`). 정지 여부는 상태에 두지 않고 원장에서 계산한다.

/// 다음 실행으로 미룬 제안 하나.
public struct LawDreamDeferred: Codable, Sendable, Equatable {
    public var world: String
    public var proposal: LawDreamProposal

    public init(world: String, proposal: LawDreamProposal) {
        self.world = world
        self.proposal = proposal
    }
}

public struct LawDreamState: Codable, Sendable, Equatable {
    /// 마지막 실행 폴더 이름(`v<yymmddhhmmss>`).
    public var lastRun: String?
    /// 마지막 실행 시각(ms UTC).
    public var lastRunAt: String?
    /// 재료로 읽은 적재 실행 요약 주소들(다시 읽지 않는다).
    public var consumedManifests: [String]
    public var deferred: [LawDreamDeferred]

    public init(lastRun: String? = nil, lastRunAt: String? = nil, consumedManifests: [String] = [], deferred: [LawDreamDeferred] = []) {
        self.lastRun = lastRun
        self.lastRunAt = lastRunAt
        self.consumedManifests = consumedManifests
        self.deferred = deferred
    }

    public var lastRunDate: Date? { lastRunAt.flatMap(LawTime.parse) }

    /// R2 의 완료된 드리밍 실행 요약(원장 키들)에서 다시 만든다. 요약이 없으면 nil.
    public static func rebuild(store: any LawObjectStore, ledgerKeys: [String]) throws -> LawDreamState? {
        var summaries: [LawDreamSummary] = []
        for key in Set(ledgerKeys).sorted() {
            for path in try store.list(prefix: LawDreamKeys.prefix(ledgerKey: key)) where path.hasSuffix("/summary.json") {
                summaries.append(try JSONDecoder().decode(LawDreamSummary.self, from: store.get(key: path)))
            }
        }
        guard let last = summaries.max(by: { $0.run < $1.run }) else { return nil }
        var consumed: [String] = []
        for summary in summaries { for key in summary.consumedManifests where !consumed.contains(key) { consumed.append(key) } }
        return LawDreamState(lastRun: last.run, lastRunAt: last.startedAt, consumedManifests: consumed, deferred: [])
    }
}

/// 상태 파일 `<상태 폴더>/state.json`. 기본 폴더는 상태 루트 `~/.agent-wiki/dream`.
public struct LawDreamStateStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public static var standardDirectory: URL { StateRootKit.url(".agent-wiki/dream") }

    public var url: URL { directory.appendingPathComponent("state.json") }

    public func load() -> LawDreamState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LawDreamState.self, from: data)
    }

    public func save(_ state: LawDreamState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}

// MARK: - R2

public enum LawDreamKeys {
    public static func prefix(ledgerKey: String) -> String { "\(ledgerKey)/runs/dream/" }

    /// `<원장 키>/runs/dream/v<yymmddhhmmss>/<이름>`
    public static func file(ledgerKey: String, run: String, name: String) -> String {
        "\(ledgerKey)/runs/dream/\(run)/\(name)"
    }

    public static func summary(ledgerKey: String, run: String) -> String { file(ledgerKey: ledgerKey, run: run, name: "summary.json") }
}

/// 드리밍 실행 요약(원장마다 하나, 그 실행 폴더의 맨 마지막 파일).
public struct LawDreamSummary: Codable, Sendable, Equatable {
    public var kind: String
    public var ledgerKey: String
    public var world: String
    public var device: String
    public var run: String
    public var trigger: String
    /// 실행 시작(ms UTC).
    public var startedAt: String
    public var finishedAt: String
    public var batch: String
    public var runtime: String?
    public var model: String?
    public var effort: String?
    public var consumedManifests: [String]
    public var applied: [LawDreamApplied]
    public var discarded: [LawDreamDiscard]
    public var deferred: Int
    public var alerts: [String]
    public var migrations: Int
    public var contents: String?
    public var report: String?
    public var aiError: String?
    public var sync: [String]
}

/// 적용한 변경 하나(공포한 기록 id 들).
public struct LawDreamApplied: Codable, Sendable, Equatable {
    public var kind: String
    public var world: String
    public var target: String?
    public var ids: [String]
    public var note: String?

    public init(kind: String, world: String, target: String?, ids: [String], note: String?) {
        self.kind = kind
        self.world = world
        self.target = target
        self.ids = ids
        self.note = note
    }
}
