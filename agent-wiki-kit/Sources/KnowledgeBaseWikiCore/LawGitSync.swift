import Foundation
import CommandKit
import InteropKit
import WikiLedgerKit

// agent-law git 정본 — 공포 직후 커밋과 `sync`(커밋 대기 처리 → pull 합집합 → push).
// 근거: docs/business-rules.md "원장 구성"·"공포·개정·폐지·원상회복", docs/architecture.md "agent-law (ledger 3)",
// docs/contracts.md "agent-law 명령"(`sync`), 결정 0007(모든 기기가 push, 결정 0003 대체).
//
// 저장소 모양: 원장 셋의 폴더(`<원장 키>/`)가 git 저장소 하나를 이룬다(`~/agent-law`).
// 원장 루트가 저장소 맨 위이거나 그 바로 아래 폴더일 때만 git 원장으로 본다 — 엉뚱한 상위 저장소에 커밋하지 않는다.
// 원격 주소는 소스에 두지 않고 저장소의 `origin` 을 쓴다.

// MARK: - git 실행기

/// git 하위 프로세스. 공용 실행기(`SafeProcessRunner`)로만 부르고 대화형 프롬프트를 끈다.
public struct LawGitRunner: Sendable {
    public struct Output: Sendable, Equatable {
        public let code: Int32
        public let stdout: String
        public let combined: String
        public var ok: Bool { code == 0 }
    }

    public typealias Execute = @Sendable (_ arguments: [String], _ directory: URL, _ timeout: TimeInterval) -> Output

    private let execute: Execute

    public init(execute: @escaping Execute) { self.execute = execute }

    /// 기본 실행기 — `/usr/bin/env git …`, `GIT_TERMINAL_PROMPT=0`, ssh 일괄 모드.
    public static let live = LawGitRunner { arguments, directory, timeout in
        var environment = ProcessInfo.processInfo.environment
        // 부모가 git 훅 안에서 돌 때 물려받는 저장소 지정을 지운다(엉뚱한 저장소에 쓰지 않게).
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_PREFIX", "GIT_OBJECT_DIRECTORY"] {
            environment.removeValue(forKey: key)
        }
        environment["PATH"] = "\(HostPlatform.homebrewBin):/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_SSH_COMMAND"] = environment["GIT_SSH_COMMAND"] ?? "ssh -o BatchMode=yes -o ConnectTimeout=10"
        let result = SafeProcessRunner.run(
            "/usr/bin/env", ["git"] + arguments, environment: environment,
            workingDirectory: directory, timeout: timeout)
        return Output(code: result.exitCode, stdout: result.stdout, combined: result.combinedOutput)
    }

    @discardableResult
    public func callAsFunction(_ arguments: [String], in directory: URL, timeout: TimeInterval = 20) -> Output {
        execute(arguments, directory, timeout)
    }
}

// MARK: - 저장소

/// 원장 루트가 속한 agent-law git 저장소.
public struct LawGitRepository: Sendable {
    /// 저장소 맨 위(`~/agent-law`).
    public let top: URL
    /// 절대 git 폴더(`<top>/.git`).
    public let gitDir: URL
    public let git: LawGitRunner

    /// 저장소 잠금 대기 상한 기본값(초). 환경 변수 `AGENT_LAW_COMMIT_LOCK_SECONDS` 로 조정한다.
    public static let defaultLockSeconds: TimeInterval = 30
    public static let lockSecondsEnvironment = "AGENT_LAW_COMMIT_LOCK_SECONDS"

    public static func lockSeconds(environment: [String: String] = ProcessInfo.processInfo.environment) -> TimeInterval {
        guard let raw = environment[lockSecondsEnvironment], let value = TimeInterval(raw), value >= 0 else {
            return defaultLockSeconds
        }
        return value
    }

    /// 저장소에서 빼는 경로(증거물은 R2, 파생 상태·세션 등록은 기기 로컬).
    public static let ignoredPatterns = ["/*/exhibits/", "/*/state/", "/*/sessions/", "/exhibits/", "/state/", "/sessions/", ".DS_Store"]

    /// 원장 루트에서 저장소를 찾는다. git 저장소가 아니거나 루트가 저장소의 맨 위·바로 아래가 아니면 nil.
    public static func locate(ledgerRoot: URL, git: LawGitRunner = .live) -> LawGitRepository? {
        var root = ledgerRoot.standardizedFileURL.resolvingSymlinksInPath()
        // 아직 기록이 없는 원장 폴더(새 복제본 등)는 저장소 맨 위인 부모에서 찾는다.
        var probe = root
        if !FileManager.default.fileExists(atPath: root.path) {
            probe = root.deletingLastPathComponent().resolvingSymlinksInPath()
            root = probe.appendingPathComponent(ledgerRoot.lastPathComponent)
            guard FileManager.default.fileExists(atPath: probe.path) else { return nil }
        }
        let top = git(["rev-parse", "--show-toplevel"], in: probe)
        let dir = git(["rev-parse", "--absolute-git-dir"], in: probe)
        guard top.ok, dir.ok else { return nil }
        let topURL = URL(fileURLWithPath: top.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            .standardizedFileURL.resolvingSymlinksInPath()
        guard topURL.path == root.path || topURL.path == root.deletingLastPathComponent().path else { return nil }
        return LawGitRepository(
            top: topURL,
            gitDir: URL(fileURLWithPath: dir.stdout.trimmingCharacters(in: .whitespacesAndNewlines)),
            git: git)
    }

    @discardableResult
    func run(_ arguments: [String], timeout: TimeInterval = 20) -> LawGitRunner.Output {
        git(arguments, in: top, timeout: timeout)
    }

    /// 저장소 기준 상대 경로.
    public func relativePath(_ url: URL) -> String? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = top.path.hasSuffix("/") ? top.path : top.path + "/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    /// 원장 기록 파일 경로인가(`objects/…` 또는 `<원장 키>/objects/…`).
    public static func isRecordPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/")
        guard path.hasSuffix(".md"), parts.count >= 2 else { return false }
        return parts[0] == "objects" || (parts.count >= 3 && parts[1] == "objects")
    }

    // MARK: 잠금

    var lockURL: URL { gitDir.appendingPathComponent("agent-law.lock") }

    /// 저장소 단위 잠금. 상한 안에 못 얻으면 nil. 프로세스가 죽으면 커널이 푼다(`flock`).
    public func acquireLock(timeout: TimeInterval) -> LawGitLock? {
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return LawGitLock(descriptor: descriptor) }
            if Date() >= deadline { break }
            usleep(50_000)
        }
        close(descriptor)
        return nil
    }

    // MARK: 커밋 대기 표시

    var pendingMarkerURL: URL { gitDir.appendingPathComponent("agent-law-pending") }

    /// 커밋 대기 표시(경로 한 줄). 잠금 없이 덧붙인다(`O_APPEND` 한 번 쓰기).
    func markPending(_ path: String) {
        let descriptor = open(pendingMarkerURL.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        let line = Array((path + "\n").utf8)
        _ = line.withUnsafeBufferPointer { write(descriptor, $0.baseAddress, $0.count) }
    }

    /// 표시된 커밋 대기 경로(중복 제거).
    public func markedPending() -> [String] {
        guard let text = try? String(contentsOf: pendingMarkerURL, encoding: .utf8) else { return [] }
        var seen = Set<String>()
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    func clearPendingMarker() {
        try? FileManager.default.removeItem(at: pendingMarkerURL)
    }

    // MARK: 작업본 상태

    struct StatusEntry: Equatable {
        let code: String
        let path: String
        var isUntrackedOrAdded: Bool { code == "??" || code == "A " || code == "AM" }
    }

    /// `git status --porcelain` 중 원장 기록 파일만.
    func recordStatus() -> [StatusEntry] {
        let out = run(["status", "--porcelain=v1", "-z", "--untracked-files=all"])
        guard out.ok else { return [] }
        var entries: [StatusEntry] = []
        var fields = out.stdout.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let field = fields.popFirst() {
            guard field.count > 3 else { continue }
            let code = String(field.prefix(2))
            let path = String(field.dropFirst(3))
            // 이름 바꿈은 원래 경로가 다음 필드로 온다.
            if code.hasPrefix("R") || code.hasPrefix("C") { _ = fields.popFirst() }
            if Self.isRecordPath(path) { entries.append(StatusEntry(code: code, path: path)) }
        }
        return entries
    }

    /// 아직 커밋되지 않은 기록 파일 수(커밋 대기).
    public func pendingCount() -> Int {
        recordStatus().filter(\.isUntrackedOrAdded).count
    }

    // MARK: 한 파일 커밋

    /// 기록 파일 하나만 커밋한다. 메시지는 `<id> <제목>` 한 줄.
    func commitRecord(path: String, message: String) -> LawGitRunner.Output {
        let add = run(["add", "--", path])
        guard add.ok else { return add }
        // 멱등 공포(같은 바이트가 이미 커밋됨)는 커밋할 것이 없다 — 성공으로 본다.
        let hasHead = run(["rev-parse", "--verify", "-q", "HEAD"]).ok
        if hasHead, run(["diff", "--cached", "--quiet", "HEAD", "--", path]).ok { return add }
        return run(["commit", "-q", "--only", "-m", message, "--", path])
    }

    /// 기록 파일에서 커밋 메시지(`<id> <제목>`)를 만든다.
    func commitMessage(forRecordAt path: String) -> String {
        let url = top.appendingPathComponent(path)
        let fallback = url.deletingPathExtension().lastPathComponent
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let parsed = LawRecordParser.parse(text) else { return fallback }
        return LawGitCommit.message(id: parsed.storedID, title: parsed.record.title ?? parsed.record.type)
    }
}

/// `flock` 잠금 손잡이. `release()` 하거나 프로세스가 끝나면 풀린다.
public final class LawGitLock: @unchecked Sendable {
    private var descriptor: Int32

    init(descriptor: Int32) { self.descriptor = descriptor }

    public func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit { release() }
}

// MARK: - 공포 직후 커밋

public enum LawGitCommitOutcome: Sendable, Equatable {
    /// 커밋함(커밋 수).
    case committed(Int)
    /// 기록은 남고 "커밋 대기"로 표시함(이유).
    case pending(String)
    /// 원장 루트가 git 저장소가 아니라 건너뜀(시험의 임시 원장 등).
    case skipped
}

public enum LawGitCommit {
    /// 커밋 메시지 — 기록 id 와 제목 한 줄.
    public static func message(id: String, title: String?) -> String {
        let oneLine = (title ?? "")
            .components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return oneLine.isEmpty ? id : "\(id) \(oneLine)"
    }

    /// 공포한 기록 파일만 커밋한다. 잠금(상한 `lockTimeout`)을 못 얻거나 git 이 실패하면 "커밋 대기"로 표시한다.
    @discardableResult
    public static func commit(
        _ enacted: [LawStoredRecord], ledgerRoot: URL,
        lockTimeout: TimeInterval = LawGitRepository.lockSeconds(), git: LawGitRunner = .live
    ) -> LawGitCommitOutcome {
        guard !enacted.isEmpty else { return .committed(0) }
        guard let repository = LawGitRepository.locate(ledgerRoot: ledgerRoot, git: git) else { return .skipped }
        let store = LawStore(root: ledgerRoot)
        let items: [(path: String, message: String)] = enacted.compactMap { stored in
            let url = store.objectURL(id: stored.id, promulgated: stored.record.promulgated)
            guard let path = repository.relativePath(url) else { return nil }
            return (path, message(id: stored.id, title: stored.record.title ?? stored.record.type))
        }
        guard let lock = repository.acquireLock(timeout: lockTimeout) else {
            items.forEach { repository.markPending($0.path) }
            return .pending("저장소 잠금을 \(Int(lockTimeout))초 안에 얻지 못함")
        }
        defer { lock.release() }
        var committed = 0
        for (index, item) in items.enumerated() {
            let result = repository.commitRecord(path: item.path, message: item.message)
            guard result.ok else {
                items[index...].forEach { repository.markPending($0.path) }
                return .pending("git 커밋 실패: \(result.combined.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            committed += 1
        }
        return .committed(committed)
    }
}

// MARK: - 동기화

/// `sync` 결과. 상태 파일(`<git 폴더>/agent-law-sync.json`)에도 같은 값을 남긴다.
public struct LawSyncOutcome: Codable, Sendable, Equatable {
    /// 이번에 커밋한 커밋 대기 기록 수.
    public var committedPending: Int
    /// 원격에서 새로 받아온 기록 파일 수.
    public var received: Int
    public var pushed: Bool
    public var branch: String
    public var head: String?
    public var messages: [String]

    public init(committedPending: Int, received: Int, pushed: Bool, branch: String, head: String?, messages: [String]) {
        self.committedPending = committedPending
        self.received = received
        self.pushed = pushed
        self.branch = branch
        self.head = head
        self.messages = messages
    }
}

public enum LawSyncError: Error, Sendable, Equatable, CustomStringConvertible {
    case notARepository(String)
    case lockTimeout(TimeInterval)
    case noOrigin
    case fetchFailed(String)
    /// 같은 경로에 다른 바이트(덧붙이기 위반). 사람이 본다.
    case divergentRecords([String])
    case git(String)

    public var description: String {
        switch self {
        case .notARepository(let path): return "agent-law git 저장소가 아님: \(path)"
        case .lockTimeout(let seconds): return "저장소 잠금을 \(Int(seconds))초 안에 얻지 못함"
        case .noOrigin: return "저장소에 origin 원격이 없음"
        case .fetchFailed(let detail): return "origin fetch 실패: \(detail)"
        case .divergentRecords(let paths):
            return "같은 경로에 다른 바이트 — 합치지 않고 멈춤(사람 확인 필요): " + paths.joined(separator: ", ")
        case .git(let detail): return detail
        }
    }
}

/// 마지막 동기화 상태(화면 표시용).
public struct LawSyncState: Codable, Sendable, Equatable {
    public var lastSync: Date
    public var pushed: Bool
    public var received: Int
    public var committedPending: Int
    public var error: String?
}

/// 화면용 요약 — 마지막 동기화 시각·커밋 대기 수·push 여부.
public struct LawSyncDisplay: Sendable, Equatable {
    public let isRepository: Bool
    public let lastSync: Date?
    public let pending: Int
    public let pushed: Bool?
    public let error: String?
}

public struct LawGitSync: Sendable {
    public let ledgerRoot: URL
    public let git: LawGitRunner
    public let lockTimeout: TimeInterval

    public init(
        ledgerRoot: URL, lockTimeout: TimeInterval = LawGitRepository.lockSeconds(), git: LawGitRunner = .live
    ) {
        self.ledgerRoot = ledgerRoot
        self.lockTimeout = lockTimeout
        self.git = git
    }

    static let networkTimeout: TimeInterval = 120

    /// 커밋 대기 커밋 → origin fetch → 덧붙이기 검사 → 합치기 → push. 잠금 안에서 한다.
    /// 드리밍 끝·예약 실행(10분)도 이 함수를 부른다.
    public func sync() -> Result<LawSyncOutcome, LawSyncError> {
        guard let repository = LawGitRepository.locate(ledgerRoot: ledgerRoot, git: git) else {
            return .failure(.notARepository(ledgerRoot.path))
        }
        guard let lock = repository.acquireLock(timeout: lockTimeout) else {
            return .failure(.lockTimeout(lockTimeout))
        }
        defer { lock.release() }
        var committed = 0
        let result = run(repository, committed: &committed)
        stamp(repository, result: result, committed: committed)
        return result
    }

    private func run(_ repository: LawGitRepository, committed: inout Int) -> Result<LawSyncOutcome, LawSyncError> {
        var messages: [String] = []
        if let error = ensureIgnore(repository, messages: &messages) { return .failure(error) }

        // 1. 커밋 대기 기록을 하나씩 커밋(메시지는 그 기록의 id·제목).
        let status = repository.recordStatus()
        let tampered = status.filter { !$0.isUntrackedOrAdded }.map(\.path)
        guard tampered.isEmpty else { return .failure(.divergentRecords(tampered)) }
        for entry in status {
            let result = repository.commitRecord(
                path: entry.path, message: repository.commitMessage(forRecordAt: entry.path))
            guard result.ok else { return .failure(.git("커밋 대기 커밋 실패(\(entry.path)): \(result.combined)")) }
            committed += 1
        }
        repository.clearPendingMarker()

        // 2. origin 에서 받아 합집합.
        guard repository.run(["remote", "get-url", "origin"]).ok else { return .failure(.noOrigin) }
        let branchOut = repository.run(["symbolic-ref", "--short", "HEAD"])
        let branch = branchOut.ok ? branchOut.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : "main"
        let fetch = repository.run(["fetch", "-q", "origin"], timeout: Self.networkTimeout)
        guard fetch.ok else { return .failure(.fetchFailed(fetch.combined.trimmingCharacters(in: .whitespacesAndNewlines))) }
        let theirs = "refs/remotes/origin/\(branch)"
        var received = 0
        if repository.run(["rev-parse", "--verify", "-q", theirs]).ok {
            switch merge(repository, theirs: theirs) {
            case .success(let count): received = count
            case .failure(let error): return .failure(error)
            }
        }

        // 3. push.
        let push = repository.run(["push", "-q", "origin", "HEAD:refs/heads/\(branch)"], timeout: Self.networkTimeout)
        if !push.ok { messages.append("push 실패: \(push.combined.trimmingCharacters(in: .whitespacesAndNewlines))") }
        let head = repository.run(["rev-parse", "--short", "HEAD"])
        return .success(LawSyncOutcome(
            committedPending: committed, received: received, pushed: push.ok, branch: branch,
            head: head.ok ? head.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil, messages: messages))
    }

    /// 덧붙이기만 하는 원장의 합치기 = 파일 합집합. 같은 경로에 다른 바이트, 원격의 기록 수정·삭제는 멈춘다.
    private func merge(_ repository: LawGitRepository, theirs: String) -> Result<Int, LawSyncError> {
        let hasHead = repository.run(["rev-parse", "--verify", "-q", "HEAD"]).ok
        var added: [String] = []
        var divergent: [String] = []
        if hasHead {
            for (code, path) in nameStatus(repository, ["diff", "--name-status", "--no-renames", "-z", "HEAD", theirs])
            where LawGitRepository.isRecordPath(path) {
                if code == "A" { added.append(path) } else if code == "M" || code == "T" { divergent.append(path) }
            }
            let base = repository.run(["merge-base", "HEAD", theirs])
            if base.ok {
                let baseID = base.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                for (code, path) in nameStatus(repository, ["diff", "--name-status", "--no-renames", "-z", baseID, theirs])
                where LawGitRepository.isRecordPath(path) && code != "A" {
                    divergent.append(path)
                }
            }
        } else {
            let listing = repository.run(["ls-tree", "-r", "--name-only", "-z", theirs])
            added = listing.stdout.split(separator: "\0").map(String.init).filter(LawGitRepository.isRecordPath)
        }
        let uniqueDivergent = Array(Set(divergent)).sorted()
        guard uniqueDivergent.isEmpty else { return .failure(.divergentRecords(uniqueDivergent)) }
        // 처음 받는 빈 저장소(HEAD 없음)에서도 빨리 감기로 받는다. 전환 단계에서 따로 init 한 기기의 역사도
        // 위 검사로 같은 경로 다른 바이트가 없음을 확인했으니 합집합으로 합친다.
        let merge = repository.run(["merge", "--no-edit", "-q", "--allow-unrelated-histories", theirs])
        guard merge.ok else {
            if hasHead { repository.run(["merge", "--abort"]) }
            return .failure(.git("합치기 실패(사람 확인 필요): \(merge.combined.trimmingCharacters(in: .whitespacesAndNewlines))"))
        }
        return .success(added.count)
    }

    private func nameStatus(_ repository: LawGitRepository, _ arguments: [String]) -> [(String, String)] {
        let out = repository.run(arguments)
        guard out.ok else { return [] }
        let fields = out.stdout.split(separator: "\0").map(String.init)
        var pairs: [(String, String)] = []
        var index = 0
        while index + 1 < fields.count {
            pairs.append((String(fields[index].prefix(1)), fields[index + 1]))
            index += 2
        }
        return pairs
    }

    /// `.gitignore` 에 증거물·파생 상태·세션 등록 제외를 보장하고, 바뀌었으면 그 파일만 커밋한다.
    private func ensureIgnore(_ repository: LawGitRepository, messages: inout [String]) -> LawSyncError? {
        let url = repository.top.appendingPathComponent(".gitignore")
        let current = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let present = Set(current.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        let missing = LawGitRepository.ignoredPatterns.filter { !present.contains($0) }
        guard !missing.isEmpty else { return nil }
        var text = current
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += missing.joined(separator: "\n") + "\n"
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch {
            return .git(".gitignore 쓰기 실패: \(error.localizedDescription)")
        }
        let commit = repository.commitRecord(path: ".gitignore", message: "chore: agent-law ignore exhibits, state, sessions")
        guard commit.ok else { return .git(".gitignore 커밋 실패: \(commit.combined)") }
        messages.append(".gitignore 준비")
        return nil
    }

    private func stamp(_ repository: LawGitRepository, result: Result<LawSyncOutcome, LawSyncError>, committed: Int) {
        let state: LawSyncState
        switch result {
        case .success(let outcome):
            state = LawSyncState(
                lastSync: Date(), pushed: outcome.pushed, received: outcome.received,
                committedPending: outcome.committedPending, error: outcome.pushed ? nil : outcome.messages.last)
        case .failure(let error):
            state = LawSyncState(lastSync: Date(), pushed: false, received: 0, committedPending: committed, error: error.description)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: Self.stateURL(repository), options: .atomic)
    }

    static func stateURL(_ repository: LawGitRepository) -> URL {
        repository.gitDir.appendingPathComponent("agent-law-sync.json")
    }

    /// 마지막 동기화 상태(없으면 nil).
    public func lastState() -> LawSyncState? {
        guard let repository = LawGitRepository.locate(ledgerRoot: ledgerRoot, git: git),
              let data = try? Data(contentsOf: Self.stateURL(repository)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LawSyncState.self, from: data)
    }

    /// 화면 표시 — 마지막 동기화 시각·커밋 대기 수·push 여부. 네트워크를 쓰지 않는다.
    public func display() -> LawSyncDisplay {
        guard let repository = LawGitRepository.locate(ledgerRoot: ledgerRoot, git: git) else {
            return LawSyncDisplay(isRepository: false, lastSync: nil, pending: 0, pushed: nil, error: nil)
        }
        let state = lastState()
        return LawSyncDisplay(
            isRepository: true, lastSync: state?.lastSync, pending: repository.pendingCount(),
            pushed: state?.pushed, error: state?.error)
    }
}
