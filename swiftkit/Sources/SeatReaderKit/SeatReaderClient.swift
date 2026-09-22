import CommandKit
import Foundation
import InteropKit

/// `agent-seat-manager` 읽기 클라이언트. 고용/해고는 소유 CLI가 정본이다.
public struct SeatReaderClient: Sendable {
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
            HostPlatform.cliBinPath("agent-seat-manager"),
            "/Applications/agent-seat-manager.app/Contents/MacOS/agent-seat-manager",
        ]
    }

    public static func resolvedExecutable() -> String? {
        executableCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private var binary: String? {
        if let executablePathOverride { return executablePathOverride }
        return Self.resolvedExecutable()
    }

    public func seats() async -> [SeatSnapshot] {
        guard let binary else { return [] }
        let r = await runner.run(binary, ["seats", "--json"], timeout: timeout)
        guard r.ok, let data = r.stdout.data(using: .utf8) else { return [] }
        return Self.decodeList(data)
    }

    public func seat(handle: String) async -> SeatSnapshot? {
        guard let binary else { return nil }
        let r = await runner.run(binary, ["seat", handle, "--json"], timeout: timeout)
        guard r.ok, let data = r.stdout.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(SeatSnapshot.self, from: data)
        } catch {
            do {
                let env = try JSONDecoder().decode(Envelope.self, from: data)
                return env.result
            } catch {
                return nil
            }
        }
    }

    public func reportMarkdown() async -> String {
        guard let binary else { return "" }
        let r = await runner.run(binary, ["report", "--stdout"], timeout: timeout)
        return r.ok ? r.trimmedStdout : ""
    }

    private struct Envelope: Decodable {
        let result: SeatSnapshot?
    }

    static func decodeList(_ data: Data) -> [SeatSnapshot] {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode([SeatSnapshot].self, from: data)
        } catch {}
        struct ListEnvelope: Decodable { let result: [SeatSnapshot]? }
        do {
            let env = try decoder.decode(ListEnvelope.self, from: data)
            if let arr = env.result {
                return arr
            }
        } catch {}
        return []
    }
}

public struct SeatSnapshot: Decodable, Sendable, Identifiable {
    public var handle: String
    public var kind: String?
    public var occupant: String?
    public var tier: String?
    public var model: String?
    public var dailyUSD: Double?

    public var id: String { handle }

    private enum CodingKeys: String, CodingKey {
        case handle, kind, occupant, tier, model, dailyUSD
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        handle = try c.decodeIfPresent(String.self, forKey: .handle) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        occupant = try c.decodeIfPresent(String.self, forKey: .occupant)
        tier = try c.decodeIfPresent(String.self, forKey: .tier)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        dailyUSD = try c.decodeIfPresent(Double.self, forKey: .dailyUSD)
    }
}
