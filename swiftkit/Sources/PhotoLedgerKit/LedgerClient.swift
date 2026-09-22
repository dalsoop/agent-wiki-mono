import Foundation
#if os(macOS)
import CommandKit
import InteropKit

/// photo-origin-ledger CLI 만 읽는다. 원본 파일은 안 건드린다.
public struct LedgerClient: Sendable {
    public var cliPath: String

    public init(cliPath: String = HostPlatform.cliBinPath("photo-origin-ledger")) {
        self.cliPath = cliPath
    }

    public func isInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: cliPath)
    }

    public func health() throws -> LedgerHealth {
        let data = try runJSON(["status", "--json"])
        return try decodeResult(LedgerHealth.self, from: data)
    }

    public func sessions() throws -> [LedgerSessionRef] {
        let data = try runJSON(["sessions", "--json"])
        return try decodeResult([LedgerSessionRef].self, from: data)
    }

    public func blobs(session: String) throws -> [LedgerBlobRef] {
        let data = try runJSON(["blobs", "--session", session, "--json"])
        return try decodeResult([LedgerBlobRef].self, from: data)
    }

    public func allBlobs() throws -> [LedgerBlobRef] {
        if let cached = CatalogCache.shared.blobsIfFresh() {
            return cached
        }
        do {
            let oneshot = try blobsAll()
            CatalogCache.shared.store(blobs: oneshot)
            return oneshot
        } catch {}
        let sessionList = try sessions()
        let blobs = try blobsParallel(sessions: sessionList)
        CatalogCache.shared.store(blobs: blobs)
        return blobs
    }

    public func clearCatalogCache() {
        CatalogCache.shared.clear()
    }

    public func blob(id: String) throws -> LedgerBlobRef? {
        let key = id.lowercased()
        return try allBlobs().first {
            $0.id == id || $0.id.lowercased().hasPrefix(key) || key.hasPrefix($0.id.lowercased())
        }
    }

    private func blobsAll() throws -> [LedgerBlobRef] {
        let data = try runJSON(["blobs", "--all", "--json"])
        return try decodeResult([LedgerBlobRef].self, from: data)
    }

    private func blobsParallel(sessions: [LedgerSessionRef]) throws -> [LedgerBlobRef] {
        guard !sessions.isEmpty else { return [] }
        let lock = NSLock()
        var collected: [LedgerBlobRef] = []
        var firstError: Error?
        let group = DispatchGroup()
        for session in sessions {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                do {
                    let rows = try self.blobs(session: session.id)
                    lock.lock()
                    collected.append(contentsOf: rows)
                    lock.unlock()
                } catch {
                    lock.lock()
                    if firstError == nil { firstError = error }
                    lock.unlock()
                }
            }
        }
        group.wait()
        if let firstError { throw firstError }
        return collected.sorted {
            if $0.sessionId != $1.sessionId { return $0.sessionId < $1.sessionId }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func runJSON(_ args: [String]) throws -> Data {
        guard isInstalled() else {
            throw PhotoLedgerError.unavailable(cliPath)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            throw PhotoLedgerError.failed(String(describing: error))
        }

        let group = DispatchGroup()
        let capture = PipeCapture()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            capture.setStdout(out.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            capture.setStderr(err.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.wait()
        ProcessWait.untilExit(process, seconds: 300)
        try? out.fileHandleForReading.close()
        try? err.fileHandleForReading.close()

        let stdout = capture.stdout
        let stderr = String(data: capture.stderr, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PhotoLedgerError.failed(
                detail.isEmpty ? "exit \(process.terminationStatus)" : detail
            )
        }
        return stdout
    }

    private func decodeResult<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(LedgerEnvelope<T>.self, from: data)
        guard envelope.ok, let result = envelope.result else {
            throw PhotoLedgerError.failed(envelope.error ?? "bad envelope")
        }
        return result
    }
}

public final class CatalogCache: @unchecked Sendable {
    public static let shared = CatalogCache()
    public var ttl: TimeInterval = 45

    private let lock = NSLock()
    private var blobs: [LedgerBlobRef]?
    private var storedAt: Date?

    public func blobsIfFresh() -> [LedgerBlobRef]? {
        lock.lock(); defer { lock.unlock() }
        guard let blobs, let storedAt,
              Date().timeIntervalSince(storedAt) < ttl else { return nil }
        return blobs
    }

    public func store(blobs: [LedgerBlobRef]) {
        lock.lock()
        self.blobs = blobs
        self.storedAt = Date()
        lock.unlock()
    }

    public func clear() {
        lock.lock()
        blobs = nil
        storedAt = nil
        lock.unlock()
    }
}

private final class PipeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _stdout = Data()
    private var _stderr = Data()

    func setStdout(_ data: Data) {
        lock.lock(); _stdout = data; lock.unlock()
    }

    func setStderr(_ data: Data) {
        lock.lock(); _stderr = data; lock.unlock()
    }

    var stdout: Data {
        lock.lock(); defer { lock.unlock() }
        return _stdout
    }

    var stderr: Data {
        lock.lock(); defer { lock.unlock() }
        return _stderr
    }
}

private struct LedgerEnvelope<T: Decodable>: Decodable {
    var ok: Bool
    var result: T?
    var error: String?
}
#endif
