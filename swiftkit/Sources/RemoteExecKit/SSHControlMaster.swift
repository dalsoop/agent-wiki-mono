import Foundation

#if canImport(Darwin)
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#elseif canImport(Glibc)
import Glibc
#endif

/// OpenSSH ControlMaster connection reuse scoped to a private per-user directory.
///
/// Each SSH target gets a deterministic socket below `/tmp/remote-exec-kit-ssh-<uid>`.
/// OpenSSH removes the socket after the configured idle lifetime on normal exit. The
/// client removes a refused/stale mux socket and retries the command exactly once.
/// These settings are passed only to RemoteExecKit's ssh processes; `~/.ssh/config`
/// is never modified.
public struct SSHControlMasterConfiguration: Sendable, Equatable {
    public var controlDirectory: URL
    public var persistSeconds: Int

    public init(
        controlDirectory: URL = Self.defaultControlDirectory,
        persistSeconds: Int = 60
    ) {
        self.controlDirectory = controlDirectory
        self.persistSeconds = persistSeconds
    }

    public static var defaultControlDirectory: URL {
        URL(fileURLWithPath: "/tmp/remote-exec-kit-ssh-\(getuid())", isDirectory: true)
    }

    func prepareControlDirectory() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: controlDirectory.path) {
            try validateControlDirectory(using: fileManager)
        } else {
            do {
                try fileManager.createDirectory(
                    at: controlDirectory,
                    withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                // Concurrent first users can both observe a missing directory. Accept
                // the loser only when the path is now the same safe directory.
                try validateControlDirectory(using: fileManager)
            }
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: controlDirectory.path
        )
    }

    func controlSocketURL(user: String, host: String, port: Int) -> URL {
        controlDirectory.appendingPathComponent(Self.controlSocketName(user: user, host: host, port: port))
    }

    func options(controlSocket: URL) -> [String] {
        [
            "-o", "ControlMaster=auto",
            "-o", "ControlPersist=\(persistSeconds)",
            "-o", "ControlPath=\(controlSocket.path)",
        ]
    }

    static func controlSocketName(user: String, host: String, port: Int) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(user)@\(host):\(port)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(hash, radix: 16) + ".sock"
    }

    static func isStaleControlSocketError(_ stderr: String) -> Bool {
        let message = stderr.lowercased()
        return (message.contains("control socket connect") && message.contains("connection refused"))
            || message.contains("master refused session request")
            || message.contains("mux_client_request_session")
    }

    private func validateControlDirectory(using fileManager: FileManager) throws {
        let attributes = try fileManager.attributesOfItem(atPath: controlDirectory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw SSHControlDirectoryError.unsafeExistingPath(controlDirectory.path)
        }
    }
}

private enum SSHControlDirectoryError: LocalizedError {
    case unsafeExistingPath(String)

    var errorDescription: String? {
        switch self {
        case .unsafeExistingPath(let path):
            return "existing control path is not a user-owned directory: \(path)"
        }
    }
}
