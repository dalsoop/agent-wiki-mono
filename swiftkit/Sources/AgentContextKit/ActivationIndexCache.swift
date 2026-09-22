import Foundation
import AgentSessionKit

/// 스킬 집계용 가벼운 세션 활성화 인덱스.
///
/// `skills`·`unused`·`coverage`·`skill-report` 는 세션 카드 전체가 아니라 **활성화 열**만 쓴다.
/// 카드는 digest·SessionScan·주입 증거를 세 번 읽어 세션당 1.3초였고(실측 2026-09-03, 60세션 78초),
/// 캐시가 없어 호출 수가 곧 스캔 수였다. 이 인덱스는 SessionScan 한 패스 결과를 transcript
/// mtime·size 로 무효화되는 파일에 둔다 — 두 번째 질문부터는 스캔이 0 이다.
public struct SessionActivationIndex: Sendable, Codable, Equatable {
    public let sessionId: String
    public let tool: String
    public let cwd: String
    public let lastActive: Date
    public let activations: [Activation]
    public let sourceMTime: TimeInterval
    public let sourceSize: Int
    /// 인덱스 규격 버전. 스캔 규칙(신호 분류·bulk 판정)이 바뀌면 올린다 — 옛 파일은 미스가 된다.
    public let formatVersion: Int

    /// v2 (2026-09-03): `source`·`bulk` 분류, agy 이름 검증.
    public static let currentFormatVersion = 2

    public init(sessionId: String, tool: String, cwd: String, lastActive: Date,
                activations: [Activation], sourceMTime: TimeInterval, sourceSize: Int,
                formatVersion: Int = SessionActivationIndex.currentFormatVersion) {
        self.sessionId = sessionId
        self.tool = tool
        self.cwd = cwd
        self.lastActive = lastActive
        self.activations = activations
        self.sourceMTime = sourceMTime
        self.sourceSize = sourceSize
        self.formatVersion = formatVersion
    }

    /// 뭉텅이 읽기로 표시된 스킬 로드가 있는 세션인가.
    public var hasBulkLoads: Bool { activations.contains(where: \.bulk) }
}

/// `~/.agent-session-context-ledger/activation-index/<id>.json` — transcript mtime·size 로 무효화.
/// 구조는 `DocIndexCache` 와 같다(문서 축·스킬 축이 같은 규약을 쓴다).
public struct ActivationIndexCache: Sendable {
    public let root: String

    /// 기본값을 두지 않는다 — 상태 루트는 `Ledger(home:)` 이 정한다(테스트 격리·재설치 안전).
    public init(root: String) {
        self.root = root
    }

    private func filePath(for sessionId: String) -> String {
        root + "/" + sessionId + ".json"
    }

    public func load(sessionId: String, sourceMTime: TimeInterval, sourceSize: Int,
                     fm: FileManager = .default) -> SessionActivationIndex? {
        guard let data = fm.contents(atPath: filePath(for: sessionId)) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let idx: SessionActivationIndex
        do {
            idx = try dec.decode(SessionActivationIndex.self, from: data)
        } catch {
            return nil  // 손상된 캐시 파일은 미스 — 다시 스캔해서 덮어쓴다.
        }
        guard idx.sourceMTime == sourceMTime, idx.sourceSize == sourceSize,
              idx.formatVersion == SessionActivationIndex.currentFormatVersion else { return nil }
        return idx
    }

    /// 저장 실패는 집계를 막지 않는다 — 캐시가 없으면 다음 호출이 다시 스캔할 뿐이다.
    /// 다만 조용히 삼키지 않고 stderr 에 한 줄 남긴다(디스크 가득·권한 문제를 알아채도록).
    public func save(_ idx: SessionActivationIndex, fm: FileManager = .default) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        do {
            try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
            let data = try enc.encode(idx)
            try data.write(to: URL(fileURLWithPath: filePath(for: idx.sessionId)), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("activation-index: 캐시 저장 실패 \(idx.sessionId): \(error)\n".utf8))
        }
    }
}

extension Ledger {
    /// 한 세션이 이만큼 **서로 다른** 스킬을 `loaded` 로만 읽었으면 뭉텅이 읽기다.
    ///
    /// 실측(2026-09-03): 7일·90일 어느 범위에서도 unused 가 0 이었다. 스킬 카탈로그 감사·
    /// 전수 grep 세션 하나가 SKILL.md 전부를 읽고, 그게 설치된 스킬 전부를 "사용" 으로 뒤집었다.
    /// 사람이 한 세션에서 손으로 부르는 스킬은 많아야 열 개 남짓이다.
    public static let bulkLoadThreshold = 25

    /// 세션 1건의 활성화 인덱스 — 캐시 적중이면 transcript 를 열지 않는다.
    ///
    /// 카드와 달리 cwd 는 주입 증거(`InjectionEvidence`)로 되찾지 않고 세션 메타의 것을 쓴다.
    /// 그 읽기 한 번이 세션당 비용의 1/3 이었고, 스킬 md 경로 해석에서 cwd 차이가 결과를
    /// 바꾸는 건 프로젝트 로컬 스킬뿐이라 집계 축에서는 감수한다.
    public func activationIndex(for ref: SessionRef) -> SessionActivationIndex {
        let key = DocIndexCache.sourceKey(for: ref)
        if let key,
           let hit = activationIndexCache.load(sessionId: ref.id, sourceMTime: key.0, sourceSize: key.1) {
            return hit
        }
        let scan = SessionScan.scan(ref)
        let cwd = ref.cwd
        let resolved = scan.activations.map { a in
            Activation(
                kind: a.kind, name: a.name, at: a.at, thought: a.thought,
                mdPath: a.mdPath
                    ?? (a.kind == .skill
                    ? ActivationTrace.skillPath(a.name, cwd: cwd, home: home)
                    : ActivationTrace.agentPath(a.name, cwd: cwd, home: home)),
                source: a.source)
        }
        let activations = Self.markBulkLoads(resolved)
        let source = key ?? (ref.lastActive.timeIntervalSince1970, 0)
        let built = SessionActivationIndex(
            sessionId: ref.id, tool: ref.tool.rawValue, cwd: cwd, lastActive: ref.lastActive,
            activations: activations, sourceMTime: source.0, sourceSize: source.1)
        if key != nil { activationIndexCache.save(built) }
        return built
    }

    /// 캐시가 없을 때만 만든다. 만들었으면 true — `index-warm` 진행 표시용.
    public func warmActivationIndex(for ref: SessionRef) -> Bool {
        if let key = DocIndexCache.sourceKey(for: ref),
           activationIndexCache.load(sessionId: ref.id, sourceMTime: key.0, sourceSize: key.1) != nil {
            return false
        }
        _ = activationIndex(for: ref)
        return true
    }

    /// `loaded` 신호로만 읽힌 서로 다른 스킬이 임계 이상이면 그 로드들을 bulk 로 표시한다.
    /// `invoked` 는 건드리지 않는다 — 런타임이 명시한 호출은 뭉텅이여도 진짜다.
    static func markBulkLoads(_ activations: [Activation]) -> [Activation] {
        let loadedNames = Set(activations
            .filter { $0.kind == .skill && $0.source == .loaded }
            .map { $0.name.lowercased() })
        guard loadedNames.count >= bulkLoadThreshold else { return activations }
        return activations.map { $0.kind == .skill && $0.source == .loaded ? $0.markedBulk() : $0 }
    }
}
