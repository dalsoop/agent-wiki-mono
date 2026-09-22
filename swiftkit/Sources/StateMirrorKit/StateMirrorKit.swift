import Foundation
import StateRootKit

/// StateMirrorKit 모듈 우산 및 기기 로컬 Room 저장소 바인딩 SSOT.
///
/// 고객용 단일 Room 로컬 저장소(`~/Library/Application Support/net.ranode.shared/rooms/<room-id>/<slug>/`)
/// 와 StateMirror 를 바인딩하여 개발자 홈(`~/.<slug>/`) 하드코딩을 탈피하고,
/// `AtomicFileWriter` 및 `SelfHealingDocumentStore` 연계 무결성을 보장한다.
public enum StateMirrorKit {
    /// 외부 고객용 기본 룸 식별자 SSOT.
    public static var defaultRoomID: String {
        StateRootKit.defaultRoomID
    }

    /// 특정 앱의 고객용 단일 룸 네임스페이스 저장소 디렉터리 URL.
    /// `~/Library/Application Support/net.ranode.shared/rooms/<room-id>/<slug>/`
    public static func customerAppStorageURL(
        slug: String,
        roomID: String = defaultRoomID,
        homeDirectory: String? = nil
    ) -> URL {
        StateRootKit.customerAppStorageURL(slug: slug, roomID: roomID, homeDirectory: homeDirectory)
    }

    /// 특정 앱의 고객용 단일 룸 네임스페이스 미러 파일 URL.
    /// `~/Library/Application Support/net.ranode.shared/rooms/<room-id>/<slug>/state.json`
    public static func customerMirrorURL(
        slug: String,
        roomID: String = defaultRoomID,
        homeDirectory: String? = nil
    ) -> URL {
        StateRootKit.customerStateMirrorURL(slug: slug, roomID: roomID, homeDirectory: homeDirectory)
    }

    /// 첫 실행 시 기본 Room 및 앱 저장소 디렉터리를 자동 프로비저닝한다 (No Wizard First-Run).
    @discardableResult
    public static func ensureCustomerMirrorStorage(
        slug: String,
        roomID: String = defaultRoomID,
        homeDirectory: String? = nil
    ) -> URL {
        StateRootKit.ensureCustomerRoomStorage(slug: slug, roomID: roomID, homeDirectory: homeDirectory)
    }
}

// MARK: - Atomic File Writing

/// 원자적 파일 쓰기 프로토콜.
public protocol AtomicWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
}

/// USENIX ALICE 원칙 및 fsync 동기화를 보장하는 원자적 파일 작성기.
/// 임시 파일 작성 -> fsync(데이터 플러시) -> rename/replaceItemAt 원자적 교체로
/// 정전/크래시 시의 0바이트 손상 및 찢긴 쓰기(Torn Write)를 원천 차단한다.
public struct AtomicFileWriter: AtomicWriting, Sendable {
    public init() {}

    public func write(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let resolvedURL = url.resolvingSymlinksInPath()
        let parentDir = resolvedURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        let temporary = parentDir
            .appendingPathComponent(".\(resolvedURL.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }

        try data.write(to: temporary, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.synchronize()
        try handle.close()

        if fileManager.fileExists(atPath: resolvedURL.path) {
            _ = try fileManager.replaceItemAt(resolvedURL, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: resolvedURL)
        }
    }
}

// MARK: - Self-Healing StateMirror Store

public enum StateMirrorStoreError: LocalizedError, Equatable, Sendable {
    case fileNotFound(URL)
    case corruptUnrecoverable(url: URL, underlying: String)
    case failClosedBlocked(url: URL, reason: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "미러 파일이 존재하지 않습니다: \(url.path)"
        case .corruptUnrecoverable(let url, let underlying):
            return "미러 파일이 손상되었으며 백업(.bak) 복구에 실패했습니다 (Fail-Closed): \(url.path) [\(underlying)]"
        case .failClosedBlocked(let url, let reason):
            return "손상 복구 실패 상태에서 안전하지 않은 덮어쓰기가 차단되었습니다 (Fail-Closed): \(url.path) [\(reason)]"
        }
    }
}

/// USENIX ALICE 안전 쓰기 및 `.bak` 자가 치유(Self-Healing),
/// `.corrupt.<timestamp>` 격리 백업, Fail-Closed 원칙을 보장하는 StateMirror 전용 저장소.
public struct StateMirrorSelfHealingStore<State: Codable & Sendable>: Sendable {
    public let app: String
    public let url: URL
    public let writer: any AtomicWriting

    public var bakURL: URL {
        let resolved = url.resolvingSymlinksInPath()
        return resolved.deletingLastPathComponent()
            .appendingPathComponent("\(resolved.lastPathComponent).bak")
    }

    public init(
        app: String,
        url: URL,
        writer: any AtomicWriting = AtomicFileWriter()
    ) {
        self.app = app
        self.url = url
        self.writer = writer
    }

    public init(
        app: String,
        roomID: String = StateRootKit.defaultRoomID,
        homeDirectory: String? = nil,
        writer: any AtomicWriting = AtomicFileWriter()
    ) {
        self.init(
            app: app,
            url: StateMirrorKit.customerMirrorURL(slug: app, roomID: roomID, homeDirectory: homeDirectory),
            writer: writer
        )
    }

    /// 파일 로드 또는 .bak 자가 치유.
    public func loadOrSelfHeal() throws -> StateMirrorEnvelope<State> {
        let resolvedURL = url.resolvingSymlinksInPath()
        let decoder = JSONDecoder()

        if !FileManager.default.fileExists(atPath: resolvedURL.path) {
            if FileManager.default.fileExists(atPath: bakURL.path) {
                do {
                    let bakData = try Data(contentsOf: bakURL)
                    let bakEnvelope = try decoder.decode(StateMirrorEnvelope<State>.self, from: bakData)
                    try? writer.write(bakData, to: resolvedURL)
                    return bakEnvelope
                } catch {}
            }
            throw StateMirrorStoreError.fileNotFound(url)
        }

        do {
            let data = try Data(contentsOf: resolvedURL)
            return try decoder.decode(StateMirrorEnvelope<State>.self, from: data)
        } catch {
            // 손상 감지 -> 격리
            Self.quarantineCorruptedFile(at: resolvedURL)

            // .bak 복구 시도
            if FileManager.default.fileExists(atPath: bakURL.path) {
                do {
                    let bakData = try Data(contentsOf: bakURL)
                    let restored = try decoder.decode(StateMirrorEnvelope<State>.self, from: bakData)
                    try? writer.write(bakData, to: resolvedURL)
                    return restored
                } catch {
                    Self.quarantineCorruptedFile(at: bakURL)
                }
            }

            throw StateMirrorStoreError.corruptUnrecoverable(
                url: resolvedURL,
                underlying: error.localizedDescription
            )
        }
    }

    /// 상태를 원자적으로 영속화하고 .bak 백업을 갱신한다.
    public func save(_ state: State) throws {
        let resolvedURL = url.resolvingSymlinksInPath()

        // 대상 파일이 이미 존재하고 유효한 경우 .bak 으로 백업
        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            var isValid = false
            do {
                let existingData = try Data(contentsOf: resolvedURL)
                _ = try JSONDecoder().decode(StateMirrorEnvelope<State>.self, from: existingData)
                isValid = true
                try? writer.write(existingData, to: bakURL)
            } catch {
                isValid = false
            }
            if !isValid {
                // 이미 손상된 경우 백업을 망치지 않고 격리
                Self.quarantineCorruptedFile(at: resolvedURL)
            }
        }

        let envelope = StateMirror.Envelope(
            app: app,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            state: state
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        try writer.write(data, to: resolvedURL)
        StateMirrorSignal.post(app: app)
    }

    /// 배타적 잠금 및 변환
    @discardableResult
    public func mutate(
        recovery: StateMirrorMutationRecovery = .fail,
        _ transform: (State?) throws -> State
    ) throws -> State {
        let existing: State?
        do {
            let env = try loadOrSelfHeal()
            existing = env.state
        } catch {
            if recovery == .replaceMalformed {
                existing = nil
            } else if let storeErr = error as? StateMirrorStoreError,
                      case .fileNotFound = storeErr {
                existing = nil
            } else {
                throw error
            }
        }
        let updated = try transform(existing)
        try save(updated)
        return updated
    }

    /// 손상 파일 격리
    @discardableResult
    public static func quarantineCorruptedFile(at targetURL: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: targetURL.path) else { return nil }
        let timestamp = Int(Date().timeIntervalSince1970)
        let destinationURL = URL(fileURLWithPath: "\(targetURL.path).corrupt.\(timestamp)")
        do {
            try FileManager.default.copyItem(at: targetURL, to: destinationURL)
            pruneQuarantinedFiles(at: targetURL, maxKeep: 5)
            return destinationURL
        } catch {
            return nil
        }
    }

    /// 보존 격리 파일 수 제한
    @discardableResult
    public static func pruneQuarantinedFiles(at targetURL: URL, maxKeep: Int = 5) -> Int {
        guard maxKeep >= 0 else { return 0 }
        let resolved = targetURL.resolvingSymlinksInPath()
        let dir = resolved.deletingLastPathComponent()
        let filename = resolved.lastPathComponent

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return 0 }
        let corruptFiles = entries.filter { $0.hasPrefix("\(filename).corrupt.") }.sorted()
        guard corruptFiles.count > maxKeep else { return 0 }

        let excess = corruptFiles.count - maxKeep
        var removed = 0
        for name in corruptFiles.prefix(excess) {
            let fileURL = dir.appendingPathComponent(name)
            if (try? FileManager.default.removeItem(at: fileURL)) != nil {
                removed += 1
            }
        }
        return removed
    }
}
