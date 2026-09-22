import Foundation
import InteropKit
import CommandKit

/// gujo 원장의 git 전송로 — 정본은 GitLab(seed), 피어(맥끼리)는 **pull-only mesh**.
///
/// 왜 이 타입이 있나: 2026-07-29 이전 전송로는 syncthing 이었고, **몇 주간 조용히 죽어 있어도
/// 아무도 몰랐다**(50 pod 폴더가 0 파일, 옆 맥 데몬 미실행). mesh 에는 ahead/behind 개념이
/// 없어서 뒤처짐이 어디에도 안 보였기 때문이다. 그래서 이 계층의 첫 책임은 동기화가 아니라
/// **뒤처짐을 관측 가능하게 만드는 것**이다 — `status` 가 `sync` 보다 먼저다.
public struct GujoSync: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    // MARK: - 프로세스

    @discardableResult
    static func run(_ tool: String, _ args: [String], cwd: URL?) -> (code: Int32, out: String) {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(HostPlatform.homebrewBin):/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_SSH_COMMAND"] = environment["GIT_SSH_COMMAND"]
            ?? "ssh -o BatchMode=yes -o ConnectTimeout=10"

        let res = SafeProcessRunner.run(
            executable: "/usr/bin/env",
            arguments: [tool] + args,
            environment: environment,
            workingDirectory: cwd,
            timeout: 10.0
        )
        return (res.exitCode, res.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func git(_ args: [String]) -> (code: Int32, out: String) {
        Self.run("git", ["-C", root.path] + args, cwd: root)
    }

    // MARK: - 상태

    public struct PeerState: Codable, Sendable, Equatable {
        public var name: String
        public var url: String
        public var reachable: Bool
        /// 피어가 우리보다 앞선 커밋 수 (fetch 된 ref 기준). 못 읽으면 nil.
        public var behindUs: Int?
        public var aheadOfUs: Int?
    }

    public struct Status: Codable, Sendable, Equatable {
        public var isRepository: Bool
        public var head: String?
        public var ahead: Int
        public var behind: Int
        public var dirty: Int
        public var remoteReachable: Bool
        public var lastSync: Date?
        public var peers: [PeerState]
        public var blobsLocal: Int
        public var blobsMissing: Int?

        public var needsAttention: Bool {
            !isRepository || behind > 0 || ahead > 0 || dirty > 0 || !remoteReachable
        }
    }

    private var lastSyncMarker: URL { root.appendingPathComponent(".git/gujo-last-sync") }

    public func loadLastSync() -> Date? {
        guard let raw = try? String(contentsOf: lastSyncMarker, encoding: .utf8),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    func stampSync(_ date: Date = Date()) {
        do { try String(date.timeIntervalSince1970).write(to: lastSyncMarker, atomically: true, encoding: .utf8) } catch { _ = error }
    }

    /// 네트워크를 건드리지 않는 로컬 판정. `probeRemote: true` 면 origin 도달성까지 확인한다.
    public func status(probeRemote: Bool = false) -> Status {
        guard git(["rev-parse", "--is-inside-work-tree"]).code == 0 else {
            return Status(isRepository: false, head: nil, ahead: 0, behind: 0, dirty: 0,
                          remoteReachable: false, lastSync: nil, peers: [],
                          blobsLocal: countBlobs(),
                          blobsMissing: GujoBlobSync.lastKnownMissing(root: root))
        }
        let head = git(["rev-parse", "--short", "HEAD"])
        let counts = git(["rev-list", "--left-right", "--count", "HEAD...@{upstream}"])
        var ahead = 0, behind = 0
        if counts.code == 0 {
            let parts = counts.out.split(whereSeparator: { $0 == "\t" || $0 == " " })
            if parts.count == 2 { ahead = Int(parts[0]) ?? 0; behind = Int(parts[1]) ?? 0 }
        }
        let dirty = git(["status", "--porcelain"]).out
            .split(separator: "\n").filter { !$0.isEmpty }.count

        var reachable = false
        if probeRemote {
            reachable = git(["ls-remote", "--exit-code", "origin", "HEAD"]).code == 0
        }

        return Status(
            isRepository: true,
            head: head.code == 0 ? head.out : nil,
            ahead: ahead, behind: behind, dirty: dirty,
            remoteReachable: probeRemote ? reachable : true,
            lastSync: loadLastSync(),
            peers: peers(),
            blobsLocal: countBlobs(),
            // 마지막 blob plan/pull 이 관측한 "원격에만 있는 수" — 네트워크 없이 읽는다.
            blobsMissing: GujoBlobSync.lastKnownMissing(root: root))
    }

    // MARK: - 피어 (pull-only)

    /// origin 을 제외한 remote = 피어. push 는 의도적으로 막아 둔다(아래 `addPeer`).
    public func peers() -> [PeerState] {
        let listing = git(["remote", "-v"])
        guard listing.code == 0 else { return [] }
        var seen: [String: String] = [:]
        for line in listing.out.split(separator: "\n") {
            let cols = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard cols.count >= 3, cols[2] == "(fetch)", cols[0] != "origin" else { continue }
            seen[cols[0]] = cols[1]
        }
        return seen.sorted { $0.key < $1.key }.map { name, url in
            let ref = git(["rev-list", "--left-right", "--count", "HEAD...\(name)/main"])
            var ahead: Int?, behind: Int?
            if ref.code == 0 {
                let parts = ref.out.split(whereSeparator: { $0 == "\t" || $0 == " " })
                if parts.count == 2 { behind = Int(parts[0]); ahead = Int(parts[1]) }
            }
            return PeerState(name: name, url: url, reachable: true,
                             behindUs: behind, aheadOfUs: ahead)
        }
    }

    /// 피어 등록. **push 는 비활성화한다** — mesh 는 pull-only 라야
    /// 체크아웃된 브랜치에 push 하는 사고가 없고 append-only union merge 와 맞는다.
    public func addPeer(name: String, url: String) -> Result<Void, GujoError> {
        guard git(["remote", "add", name, url]).code == 0 else {
            return .failure(.git("피어 추가 실패: \(name)"))
        }
        _ = git(["remote", "set-url", "--push", name, "DISABLED_pull_only_mesh"])
        return .success(())
    }

    public func removePeer(name: String) -> Result<Void, GujoError> {
        guard name != "origin" else { return .failure(.refused("origin 은 피어가 아니다(시드)")) }
        guard git(["remote", "remove", name]).code == 0 else {
            return .failure(.git("피어 제거 실패: \(name)"))
        }
        return .success(())
    }

    // MARK: - 동기화

    public struct SyncOutcome: Codable, Sendable, Equatable {
        public var fetched: [String]
        public var merged: Bool
        public var pushed: Bool
        public var head: String?
        public var messages: [String]
    }

    /// 시드(origin) 와 왕복. `peer` 를 주면 그 피어에서 **fetch·merge 만** 한다(push 안 함).
    public func sync(peer: String? = nil) -> Result<SyncOutcome, GujoError> {
        guard git(["rev-parse", "--is-inside-work-tree"]).code == 0 else {
            return .failure(.notARepository(root.path))
        }
        var messages: [String] = []
        var fetched: [String] = []

        if let peer {
            let fetch = git(["fetch", peer])
            guard fetch.code == 0 else { return .failure(.git("피어 fetch 실패: \(fetch.out)")) }
            fetched.append(peer)
            let merge = git(["merge", "--no-edit", "\(peer)/main"])
            guard merge.code == 0 else { return .failure(.git("피어 merge 실패: \(merge.out)")) }
            messages.append(merge.out)
            stampSync()
            return .success(SyncOutcome(fetched: fetched, merged: true, pushed: false,
                                        head: git(["rev-parse", "--short", "HEAD"]).out,
                                        messages: messages))
        }

        let fetch = git(["fetch", "origin"])
        guard fetch.code == 0 else { return .failure(.unreachable("origin fetch 실패: \(fetch.out)")) }
        fetched.append("origin")

        let merge = git(["merge", "--no-edit", "origin/main"])
        guard merge.code == 0 else { return .failure(.git("merge 실패(수동 해소 필요): \(merge.out)")) }
        messages.append(merge.out)

        let push = git(["push", "origin", "HEAD:main"])
        let pushed = push.code == 0
        if !pushed { messages.append("push 실패: \(push.out)") }
        stampSync()

        return .success(SyncOutcome(fetched: fetched, merged: true, pushed: pushed,
                                    head: git(["rev-parse", "--short", "HEAD"]).out,
                                    messages: messages))
    }

    // MARK: - blobs

    /// `blobs/<앞2자>/<sha256>` — git 밖(대용량)이라 garage(S3)가 시드다.
    public func countBlobs() -> Int {
        let dir = root.appendingPathComponent("blobs")
        guard let walker = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var count = 0
        for case let url as URL in walker {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { count += 1 }
        }
        return count
    }
}

public enum GujoError: Error, Sendable, Equatable {
    case notARepository(String)
    case git(String)
    case unreachable(String)
    case refused(String)

    public var message: String {
        switch self {
        case .notARepository(let path): "git 저장소가 아니다: \(path)"
        case .git(let detail): detail
        case .unreachable(let detail): detail
        case .refused(let detail): detail
        }
    }
}
