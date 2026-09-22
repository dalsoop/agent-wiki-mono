import CommandKit
import Foundation
import InteropKit

/// `feature-backlog-studio` / `feature-backlogctl` 클라이언트. 제품 백로그 상태의 소유 CLI를 호출한다.
public struct BacklogClient: Sendable {
    private let runner: any CommandRunning
    private let timeout: TimeInterval
    private let executablePathOverride: String?

    public init(
        runner: any CommandRunning = ProcessCommandRunner(),
        executablePath: String? = nil,
        timeout: TimeInterval = 15
    ) {
        self.runner = runner
        self.executablePathOverride = executablePath
        self.timeout = timeout
    }

    public static var executableCandidates: [String] {
        [
            HostPlatform.cliBinPath("feature-backlog-studio"),
            HostPlatform.cliBinPath("feature-backlogctl"),
            "/usr/local/bin/feature-backlog-studio",
            "/usr/local/bin/feature-backlogctl",
        ]
    }

    public static func resolvedExecutable() -> String? {
        executableCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private var binary: String? {
        if let executablePathOverride { return executablePathOverride }
        return Self.resolvedExecutable()
    }

    public func list(status: String? = nil, product: String? = nil, kind: String? = nil) async -> [BacklogItem] {
        guard let binary else { return [] }
        var args = ["list", "--json"]
        if let status { args += ["--status", status] }
        if let product { args += ["--product", product] }
        if let kind { args += ["--kind", kind] }
        let r = await runner.run(binary, args, timeout: timeout)
        guard r.ok, let data = r.stdout.data(using: .utf8) else { return [] }
        return Self.decodeList(data)
    }

    public func updateStatus(id: String, status: String) async -> Bool {
        guard let binary else { return false }
        let r = await runner.run(binary, ["update-status", id, "--status", status], timeout: timeout)
        return r.ok
    }

    static func decodeList(_ data: Data) -> [BacklogItem] {
        do {
            return try BacklogCodec.decode([BacklogItem].self, from: data)
        } catch {
            struct Envelope: Decodable {
                let result: [BacklogItem]?
                let items: [BacklogItem]?
            }
            do {
                let env = try JSONDecoder().decode(Envelope.self, from: data)
                return env.result ?? env.items ?? []
            } catch {
                return []
            }
        }
    }
}
