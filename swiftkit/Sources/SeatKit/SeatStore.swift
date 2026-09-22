import Foundation
import StateRootKit
import LocalizationKit

/// 자리 정본. 소비자(agent-chat 등)가 `@handle` 을 풀 때 읽는 파일이다.
///
///     ~/.agent-seats/seats.json    자리들
///     ~/.agent-seats/roster.json   고용 가능한 후보 캐시
///
/// 의존은 한 방향이다 — 소비자가 자리를 읽지, 자리가 소비자를 모른다. 그래서 chat 뿐 아니라
/// hermes·worker-orchestrator 도 같은 자리를 쓸 수 있다.
public struct SeatStore: Sendable {
    public let root: URL

    /// `AGENT_SEATS_HOME` 으로 위치를 바꾼다 — `NSHomeDirectory()` 가 `HOME` 을 무시하므로
    /// 격리 실행·테스트에는 이 변수가 유일한 경로다.
    ///
    /// 기본 경로는 **호스트 SSOT** (`StateRootKit.hostPath`) — 자리 명부는 personal/family/
    /// silneobal 자리를 한 보드에 둔다. tenant `current-context` 로 `~/.tenants/<slug>/` 에
    /// 가려지면 wire-sync·ps 가 빈 보드를 보고 "변경 없음" 이 된다(2026-08-18 실측).
    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else if let override = ProcessInfo.processInfo.environment["AGENT_SEATS_HOME"], !override.isEmpty {
            self.root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.root = URL(fileURLWithPath: StateRootKit.hostPath(".agent-seats"), isDirectory: true)
        }
    }

    public var seatsURL: URL { root.appendingPathComponent("seats.json") }
    public var rosterURL: URL { root.appendingPathComponent("roster.json") }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func ensureDir() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - 자리

    public func seats() -> [Seat] {
        do {
            let data = try Data(contentsOf: seatsURL)
            return try Self.decoder.decode([Seat].self, from: data).sorted { $0.handle < $1.handle }
        } catch {
            // 원장이 없거나 깨진 첫 기동 — 빈 보드.
            return []
        }
    }

    public func seat(_ handle: String) -> Seat? {
        seats().first { $0.handle.caseInsensitiveCompare(handle) == .orderedSame }
    }

    public func save(_ seats: [Seat]) throws {
        try ensureDir()
        try Self.encoder.encode(seats).write(to: seatsURL, options: .atomic)
    }

    /// 같은 핸들이면 갱신 — 고용은 멱등이어야 한다(같은 자리를 두 번 만들지 않는다).
    public func upsert(_ seat: Seat) throws {
        try mutate { all in
            all.removeAll { $0.handle.caseInsensitiveCompare(seat.handle) == .orderedSame }
            all.append(seat)
        }
    }

    public func remove(_ handle: String) throws {
        try mutate { all in
            all.removeAll { $0.handle.caseInsensitiveCompare(handle) == .orderedSame }
        }
    }

    /// 읽기→고치기→쓰기를 배타 잠금 안에서 한다.
    ///
    /// GUI 와 CLI 가 동시에 자리를 만질 수 있다. 잠금 없이 하면 나중에 쓴 쪽이 상대의
    /// 변경을 통째로 덮어써 자리가 조용히 사라진다.
    private func mutate(_ body: (inout [Seat]) -> Void) throws {
        try ensureDir()
        let lock = root.appendingPathComponent(".seats.lock")
        let fd = open(lock.path, O_WRONLY | O_CREAT | O_EXLOCK, 0o644)
        defer { if fd >= 0 { close(fd) } }

        var all = seats()
        body(&all)
        try Self.encoder.encode(all).write(to: seatsURL, options: .atomic)
    }

    // MARK: - 로스터

    public func roster() -> [RosterEntry] {
        do {
            let data = try Data(contentsOf: rosterURL)
            return try Self.decoder.decode([RosterEntry].self, from: data).sorted { $0.cli < $1.cli }
        } catch {
            // 스캔 전 캐시 없음 — 빈 후보.
            return []
        }
    }

    public func saveRoster(_ entries: [RosterEntry]) throws {
        try ensureDir()
        try Self.encoder.encode(entries).write(to: rosterURL, options: .atomic)
    }
}

public enum SeatError: Error, CustomStringConvertible {
    case noSuchSeat(String)
    case alreadyHired(String)
    case provisioningFailed(String)
    case reclaimFailed(String, String)
    /// 한 작업 경로에 자리가 둘 이상 — 파일 충돌·권한 경계 붕괴의 온상.
    case pathCollision(handle: String, path: String, occupiedBy: [String])
    case sliceCreateFailed(String)

    public var description: String {
        switch self {
        case .noSuchSeat(let h):
            return CLILocalization.format("SeatStore.return", h)
        case .alreadyHired(let h):
            return CLILocalization.format("SeatStore.return-2", h)
        case .provisioningFailed(let why):
            return CLILocalization.format("SeatStore.return-3", why)
        case .reclaimFailed(let handle, let why):
            return CLILocalization.format("SeatStore.return-4", handle, why)
        case .pathCollision(let handle, let path, let others):
            let who = others.map { "@\($0)" }.joined(separator: ", ")
            return CLILocalization.format("SeatStore.return-5", handle, who, path)
                + "자리마다 worktree 또는 --slice-under 로 갈라라. "
                + "정말 공유해야 하면 --allow-shared-path"
        case .sliceCreateFailed(let why):
            return CLILocalization.format("SeatStore.return-6", why)
        }
    }
}
