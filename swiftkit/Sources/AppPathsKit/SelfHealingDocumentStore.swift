import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - AliceSafeWriter (USENIX ALICE 5-step safe write)

/// USENIX ALICE 5단계 안전 쓰기 SSOT.
///
/// 1단계: 임시 파일(.tmp)에 쓰기
/// 2단계: F_FULLFSYNC (데이터 디스크 강제 동기화)
/// 3단계: .bak 갱신 (기존 파일 안전 백업)
/// 4단계: rename (.tmp -> 대상 파일 경로 원자적 교체)
/// 5단계: 부모 디렉터리 F_FULLFSYNC (디렉터리 엔트리 메타데이터 영속화)
public enum AliceSafeWriter: Sendable {
    public static func write(data: Data, to targetURL: URL) throws {
        let resolvedURL = targetURL.resolvingSymlinksInPath()
        let parentURL = resolvedURL.deletingLastPathComponent()

        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let filename = resolvedURL.lastPathComponent
        let tempURL = parentURL.appendingPathComponent(".\(filename).tmp.\(ProcessInfo.processInfo.processIdentifier).\(DispatchTime.now().uptimeNanoseconds)")

        // 1. .tmp 파일 쓰기
        #if canImport(Darwin)
        let fd = Darwin.open(tempURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        #elseif canImport(Glibc)
        let fd = Glibc.open(tempURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        #endif
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var writeError: Error?
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var bytesRemaining = rawBuffer.count
            var currentPtr = baseAddress
            while bytesRemaining > 0 {
                #if canImport(Darwin)
                let written = Darwin.write(fd, currentPtr, bytesRemaining)
                #elseif canImport(Glibc)
                let written = Glibc.write(fd, currentPtr, bytesRemaining)
                #endif
                if written < 0 {
                    if errno == EINTR { continue }
                    writeError = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    return
                }
                bytesRemaining -= written
                currentPtr = currentPtr.advanced(by: written)
            }
        }

        if let writeError {
            #if canImport(Darwin)
            Darwin.close(fd)
            #elseif canImport(Glibc)
            Glibc.close(fd)
            #endif
            try? FileManager.default.removeItem(at: tempURL)
            throw writeError
        }

        // 2. F_FULLFSYNC
        #if canImport(Darwin)
        if fcntl(fd, F_FULLFSYNC) == -1 {
            if fsync(fd) == -1 {
                let err = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                Darwin.close(fd)
                try? FileManager.default.removeItem(at: tempURL)
                throw err
            }
        }
        Darwin.close(fd)
        #elseif canImport(Glibc)
        if fsync(fd) == -1 {
            let err = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            Glibc.close(fd)
            try? FileManager.default.removeItem(at: tempURL)
            throw err
        }
        Glibc.close(fd)
        #endif

        // 3. .bak 갱신
        let bakURL = parentURL.appendingPathComponent("\(filename).bak")
        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            if FileManager.default.fileExists(atPath: bakURL.path) {
                do { try FileManager.default.removeItem(at: bakURL) } catch {}
            }
            #if canImport(Darwin)
            // APFS Copy-on-Write (CoW) clonefile 시도 (I/O 0ms, 물리 복사 생략 및 Torn Write 원천 차단)
            let cloned = resolvedURL.withUnsafeFileSystemRepresentation { src -> Bool in
                guard let src = src else { return false }
                return bakURL.withUnsafeFileSystemRepresentation { dst -> Bool in
                    guard let dst = dst else { return false }
                    return clonefile(src, dst, 0) == 0
                }
            }
            if !cloned {
                // 비 APFS 볼륨(HFS+, FAT, SMB 등) 및 에러 시 안전한 fallback
                do {
                    try FileManager.default.copyItem(at: resolvedURL, to: bakURL)
                } catch {
                    _ = error
                }
            }
            #else
            do {
                try FileManager.default.copyItem(at: resolvedURL, to: bakURL)
            } catch {
                _ = error
            }
            #endif
        }

        // 4. rename (.tmp -> 대상 파일 경로로 원자적 교체)
        if rename(tempURL.path, resolvedURL.path) != 0 {
            let err = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? FileManager.default.removeItem(at: tempURL)
            throw err
        }

        // 5. 부모 디렉터리 F_FULLFSYNC (디렉터리 엔트리 갱신 영속화)
        #if canImport(Darwin)
        let dirFd = Darwin.open(parentURL.path, O_RDONLY)
        if dirFd >= 0 {
            if fcntl(dirFd, F_FULLFSYNC) == -1 {
                _ = fsync(dirFd)
            }
            Darwin.close(dirFd)
        }
        #elseif canImport(Glibc)
        let dirFd = Glibc.open(parentURL.path, O_RDONLY)
        if dirFd >= 0 {
            _ = fsync(dirFd)
            Glibc.close(dirFd)
        }
        #endif
    }
}

// MARK: - SelfHealingStoreError

public enum SelfHealingStoreError: LocalizedError, Equatable, Sendable {
    case fileNotFound(URL)
    case corruptUnrecoverable(url: URL, underlying: String)
    case failClosedBlocked(url: URL, reason: String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "파일이 존재하지 않습니다: \(url.path)"
        case .corruptUnrecoverable(let url, let underlying):
            return "파일이 손상되었으며 백업(.bak) 복구에 실패했습니다 (Fail-Closed): \(url.path) [\(underlying)]"
        case .failClosedBlocked(let url, let reason):
            return "손상 복구 실패 상태에서 안전하지 않은 덮어쓰기가 차단되었습니다 (Fail-Closed): \(url.path) [\(reason)]"
        }
    }
}

// MARK: - SelfHealingDocumentStore

/// USENIX ALICE 5단계 안전 쓰기 및 `.bak` 자가 치유(Self-Healing),
/// `.corrupt.<timestamp>` 격리 백업, Fail-Closed 원칙을 보장하는 제네릭 상태 저장소.
public struct SelfHealingDocumentStore<Value: Codable>: Sendable {
    public let url: URL
    public let dateCoding: JSONDateCoding
    public let defaultFactory: (@Sendable () -> Value)?

    public var bakURL: URL {
        let resolved = url.resolvingSymlinksInPath()
        return resolved.deletingLastPathComponent()
            .appendingPathComponent("\(resolved.lastPathComponent).bak")
    }

    public var lockURL: URL {
        let resolved = url.resolvingSymlinksInPath()
        return resolved.deletingLastPathComponent()
            .appendingPathComponent(".\(resolved.lastPathComponent).lock")
    }

    public init(
        url: URL,
        dateCoding: JSONDateCoding = .deferred,
        default defaultFactory: (@Sendable () -> Value)? = nil
    ) {
        self.url = url
        self.dateCoding = dateCoding
        self.defaultFactory = defaultFactory
    }

    public init(
        url: URL,
        dateCoding: JSONDateCoding = .deferred,
        default defaultValue: @autoclosure @escaping @Sendable () -> Value
    ) {
        self.init(url: url, dateCoding: dateCoding, default: defaultValue)
    }

    public static func iso8601(
        url: URL,
        default defaultFactory: (@Sendable () -> Value)? = nil
    ) -> SelfHealingDocumentStore<Value> {
        SelfHealingDocumentStore(url: url, dateCoding: .iso8601, default: defaultFactory)
    }

    /// 파일이 없으면 기본값, 손상 시 격리 후 .bak 자가 치유를 시도하고,
    /// 복구 실패 시 Fail-Closed 원칙에 따라 `SelfHealingStoreError.corruptUnrecoverable`을 throw합니다.
    public func loadOrSelfHeal(default defaultFallback: Value? = nil) throws -> Value {
        let resolvedURL = url.resolvingSymlinksInPath()

        // 1. 파일이 없는 경우
        if !FileManager.default.fileExists(atPath: resolvedURL.path) {
            if FileManager.default.fileExists(atPath: bakURL.path) {
                do {
                    let bakData = try Data(contentsOf: bakURL)
                    let bakValue = try decoder().decode(Value.self, from: bakData)
                    do { try AliceSafeWriter.write(data: bakData, to: resolvedURL) } catch {}
                    return bakValue
                } catch {}
            }
            if let fallback = defaultFallback ?? defaultFactory?() {
                return fallback
            }
            throw SelfHealingStoreError.fileNotFound(url)
        }

        // 2. 정상 로드 시도
        do {
            let data = try Data(contentsOf: resolvedURL)
            return try decoder().decode(Value.self, from: data)
        } catch {
            // 3. 파일 손상 감지 -> 격리 백업 (.corrupt.<timestamp>)
            let quarantinedURL = quarantineCorruptedFile(at: resolvedURL)
            let message = "[AppPathsKit.SelfHealingDocumentStore] Warning: State file corrupted at \(resolvedURL.path), quarantined to \(quarantinedURL?.path ?? "unknown"). Error: \(error)\n"
            if let msgData = message.data(using: .utf8) {
                FileHandle.standardError.write(msgData)
            }

            // 4. 자가 치유 (.bak) 시도
            if FileManager.default.fileExists(atPath: bakURL.path) {
                do {
                    let bakData = try Data(contentsOf: bakURL)
                    let restoredValue = try decoder().decode(Value.self, from: bakData)
                    // 복구 성공: 원본 파일로 복원 영속화
                    try? AliceSafeWriter.write(data: bakData, to: resolvedURL)
                    let healMessage = "[AppPathsKit.SelfHealingDocumentStore] Self-healed state file from backup: \(bakURL.path) -> \(resolvedURL.path)\n"
                    if let msgData = healMessage.data(using: .utf8) {
                        FileHandle.standardError.write(msgData)
                    }
                    return restoredValue
                } catch {
                    // .bak 도 손상됨: 격리 백업
                    quarantineCorruptedFile(at: bakURL)
                    let bakCorruptMsg = "[AppPathsKit.SelfHealingDocumentStore] Backup file \(bakURL.path) is also corrupted: \(error)\n"
                    if let msgData = bakCorruptMsg.data(using: .utf8) {
                        FileHandle.standardError.write(msgData)
                    }
                }
            }

            // 5. Fail-Closed: 복구 불가능한 손상 시 절대 빈 배열을 반환하지 않고 throw
            throw SelfHealingStoreError.corruptUnrecoverable(
                url: resolvedURL,
                underlying: error.localizedDescription
            )
        }
    }

    /// 관대한 로드: UI 표시용. 복구 실패 시에만 fallback 반환.
    public func load(default defaultValue: @autoclosure () -> Value) -> Value {
        do {
            return try loadOrSelfHeal(default: defaultValue())
        } catch {
            return defaultValue()
        }
    }

    /// 기본 팩토리가 설정된 경우의 편의 로드
    public func load() -> Value {
        if let factory = defaultFactory {
            return load(default: factory())
        }
        preconditionFailure("Default factory not configured for SelfHealingDocumentStore at \(url.path)")
    }

    /// USENIX ALICE 5단계 안전 쓰기를 통해 데이터를 영속화합니다.
    ///
    /// 대상 파일이 존재하나 손상된 상태인 경우, 유효한 .bak 백업이 손상 데이터로 덮어써지지 않도록 보호하고
    /// 손상 원본을 우선 격리(quarantine)합니다.
    public func save(_ value: Value) throws {
        let resolvedURL = url.resolvingSymlinksInPath()

        // Fail-Closed 가드: 대상 파일이 이미 존재하면 무결성 검증
        if FileManager.default.fileExists(atPath: resolvedURL.path) {
            var isCurrentValid = false
            do {
                let currentData = try Data(contentsOf: resolvedURL)
                _ = try decoder().decode(Value.self, from: currentData)
                isCurrentValid = true
            } catch {
                isCurrentValid = false
            }

            if !isCurrentValid {
                // 대상 파일이 손상된 상태 -> 손상 원본을 안전 격리 후 제거하여 백업 파괴 방지
                quarantineCorruptedFile(at: resolvedURL)
                do {
                    try FileManager.default.removeItem(at: resolvedURL)
                } catch {
                    _ = error
                }
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = dateCoding.encodingStrategy
        let data = try encoder.encode(value)
        try AliceSafeWriter.write(data: data, to: url)
    }

    /// TwoTierFileLock 배타적 잠금 하에서 값을 읽고(loadOrSelfHeal) 수정 후 저장(save)하는 원자적 트랜잭션.
    /// 손상 감지 시 후속 save 호출을 원천 차단하여 빈 상태로의 덮어쓰기를 방지합니다 (Fail-Closed).
    public static var defaultLockTimeoutSeconds: TimeInterval { TwoTierFileLock.defaultLockTimeout }

    /// TwoTierFileLock 배타적 잠금 하에서 값을 읽고(loadOrSelfHeal) 수정 후 저장(save)하는 원자적 트랜잭션.
    /// 손상 감지 시 후속 save 호출을 원천 차단하여 빈 상태로의 덮어쓰기를 방지합니다 (Fail-Closed).
    @discardableResult
    public func mutate<R>(
        timeout: TimeInterval = defaultLockTimeoutSeconds,
        _ body: (inout Value) throws -> R
    ) throws -> R {
        try TwoTierFileLock.withLock(at: lockURL, exclusive: true, timeout: timeout) {
            var value = try loadOrSelfHeal()
            let result = try body(&value)
            try save(value)
            return result
        }
    }

    /// 손상된 파일을 `url.path + ".corrupt." + timestamp` 경로로 복사 격리(quarantine)합니다.
    @discardableResult
    public func quarantineCorruptedFile(at targetURL: URL) -> URL? {
        Self.quarantineCorruptedFile(at: targetURL)
    }

    @discardableResult
    public static func quarantineCorruptedFile(at targetURL: URL) -> URL? {
        guard FileManager.default.fileExists(atPath: targetURL.path) else { return nil }
        let timestamp = Int(Date().timeIntervalSince1970)
        let dir = targetURL.deletingLastPathComponent()
        let filename = targetURL.lastPathComponent

        var targetData: Data?
        do {
            targetData = try Data(contentsOf: targetURL)
        } catch {
            targetData = nil
        }

        if let currentData = targetData {
            var existingEntries: [String] = []
            do {
                existingEntries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            } catch {
                existingEntries = []
            }
            let corruptBackups = existingEntries.filter { $0.hasPrefix("\(filename).corrupt.") }.sorted()
            if let latest = corruptBackups.last {
                let latestURL = dir.appendingPathComponent(latest)
                var latestData: Data?
                do {
                    latestData = try Data(contentsOf: latestURL)
                } catch {
                    latestData = nil
                }
                if latestData == currentData {
                    pruneQuarantinedFiles(at: targetURL, maxKeep: 5)
                    return latestURL
                }
            }
        }

        var destinationURL = URL(fileURLWithPath: "\(targetURL.path).corrupt.\(timestamp)")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            destinationURL = URL(fileURLWithPath: "\(targetURL.path).corrupt.\(timestamp).\(DispatchTime.now().uptimeNanoseconds)")
        }
        do {
            try FileManager.default.copyItem(at: targetURL, to: destinationURL)
            pruneQuarantinedFiles(at: targetURL, maxKeep: 5)
            return destinationURL
        } catch {
            let message = "[AppPathsKit.SelfHealingDocumentStore] Failed to quarantine corrupt file at \(targetURL.path): \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
            return nil
        }
    }

    /// Bounded Quarantine: 손상된 격리 파일(.corrupt.<timestamp>)이 무한 누적되지 않도록
    /// 최신 `maxKeep`개만 유지하고 이전 격리 파일을 자동 정리합니다.
    ///
    /// - Parameter maxKeep: 보존할 최대 격리 파일 개수 (기본값: 5)
    /// - Returns: 정리(삭제)된 오래된 격리 파일 개수
    @discardableResult
    public func pruneQuarantinedFiles(maxKeep: Int = 5) -> Int {
        Self.pruneQuarantinedFiles(at: url, maxKeep: maxKeep)
    }

    /// Bounded Quarantine: 지정된 대상 파일의 격리 파일(.corrupt.<timestamp>) 중
    /// 최신 `maxKeep`개만 유지하고 이전 격리 파일을 자동 정리합니다.
    ///
    /// - Parameters:
    ///   - targetURL: 원본 파일 URL
    ///   - maxKeep: 보존할 최대 격리 파일 개수 (기본값: 5)
    /// - Returns: 정리(삭제)된 오래된 격리 파일 개수
    @discardableResult
    public static func pruneQuarantinedFiles(at targetURL: URL, maxKeep: Int = 5) -> Int {
        guard maxKeep >= 0 else { return 0 }
        let resolved = targetURL.resolvingSymlinksInPath()
        let dir = resolved.deletingLastPathComponent()
        let filename = resolved.lastPathComponent

        guard let existingEntries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return 0
        }
        let prefix = "\(filename).corrupt."
        let corruptFiles = existingEntries.filter { $0.hasPrefix(prefix) }
        guard corruptFiles.count > maxKeep else { return 0 }

        // 수정 시각(또는 이름) 기준 오름차순(오래된 파일 먼저) 정렬
        let sortedEntries = corruptFiles.sorted { f1, f2 in
            let p1 = dir.appendingPathComponent(f1).path
            let p2 = dir.appendingPathComponent(f2).path
            let m1 = (try? FileManager.default.attributesOfItem(atPath: p1)[.modificationDate] as? Date) ?? .distantPast
            let m2 = (try? FileManager.default.attributesOfItem(atPath: p2)[.modificationDate] as? Date) ?? .distantPast
            if m1 != m2 {
                return m1 < m2
            }
            return f1 < f2
        }

        let excessCount = sortedEntries.count - maxKeep
        var removedCount = 0
        for entry in sortedEntries.prefix(excessCount) {
            let itemURL = dir.appendingPathComponent(entry)
            do {
                try FileManager.default.removeItem(at: itemURL)
                removedCount += 1
            } catch {
                _ = error // 정리 실패는 무시하고 다음 진행
            }
        }
        return removedCount
    }

    /// 대상 파일이 존재하나 손상되어 복구 불가능한 상태(Fail-Closed)인지 여부를 검사합니다.
    public func isCorruptedAndUnrecoverable() -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolved.path) else { return false }
        var isResolvedValid = false
        do {
            let data = try Data(contentsOf: resolved)
            _ = try decoder().decode(Value.self, from: data)
            isResolvedValid = true
        } catch {
            isResolvedValid = false
        }
        if isResolvedValid { return false }

        guard FileManager.default.fileExists(atPath: bakURL.path) else { return true }
        var isBakValid = false
        do {
            let bakData = try Data(contentsOf: bakURL)
            _ = try decoder().decode(Value.self, from: bakData)
            isBakValid = true
        } catch {
            isBakValid = false
        }
        return !isBakValid
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = dateCoding.decodingStrategy
        return decoder
    }
}
