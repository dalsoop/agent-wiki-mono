import Foundation
import CommandKit

public protocol VPNServiceInventoryProviding: Sendable {
    func services() async -> [VPNService]
}

public protocol VPNServiceInventoryLoading: Sendable {
    func loadServices() async throws -> [VPNService]
}

public enum VPNInventoryError: Error, Equatable, LocalizedError, Sendable {
    case commandFailed(exitCode: Int32, message: String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let exitCode, let message):
            return message.isEmpty
                ? "scutil --nc list failed with exit code \(exitCode)"
                : message
        case .unavailable(let message):
            return message
        }
    }
}

public struct VPNSystemInventory:
    VPNServiceInventoryProviding,
    VPNServiceInventoryLoading,
    Sendable
{
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func services() async -> [VPNService] {
        do {
            let result = try await loadServices()
            if !result.isEmpty {
                return result
            }
        } catch {}
        // scutil can transiently fail when Process.run() hits EBADF after
        // sleep/wake. Retry once after a short delay.
        try? await Task.sleep(nanoseconds: 200_000_000)
        do {
            return try await loadServices()
        } catch {
            return []
        }
    }

    public func loadServices() async throws -> [VPNService] {
        #if os(macOS)
        let listResult = await runner.run("/usr/sbin/scutil", ["--nc", "list"])
        guard listResult.ok else {
            throw VPNInventoryError.commandFailed(
                exitCode: listResult.exitCode,
                message: listResult.stderr.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
        }

        var listedServices = Self.parseList(listResult.stdout)
        for index in listedServices.indices where listedServices[index].isConnected {
            let statusResult = await runner.run(
                "/usr/sbin/scutil",
                ["--nc", "status", listedServices[index].id]
            )
            guard statusResult.ok else { continue }
            let service = listedServices[index]
            listedServices[index] = VPNService(
                id: service.id,
                name: service.name,
                providerBundleID: service.providerBundleID,
                status: service.status,
                interfaceName: Self.parseInterface(statusResult.stdout)
            )
        }
        return listedServices
        #else
        throw VPNInventoryError.unavailable(
            "VPN service inventory requires macOS"
        )
        #endif
    }

    static func parseList(_ text: String) -> [VPNService] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            parseListLine(String(line))
        }
    }

    static func parseInterface(_ text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == "InterfaceName"
            else { continue }

            let interfaceName = parts[1].trimmingCharacters(in: .whitespaces)
            return interfaceName.isEmpty ? nil : interfaceName
        }
        return nil
    }

    private static func parseListLine(_ line: String) -> VPNService? {
        guard let statusStart = line.firstIndex(of: "("),
              let statusEnd = line[statusStart...].firstIndex(of: ")")
        else { return nil }

        let providerMarker = " VPN ("
        guard let providerMarkerRange = line.range(
            of: providerMarker,
            range: statusEnd..<line.endIndex
        ) else { return nil }

        let id = line[line.index(after: statusEnd)..<providerMarkerRange.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty else { return nil }

        let providerStart = providerMarkerRange.upperBound
        guard let providerEnd = line[providerStart...].firstIndex(of: ")") else { return nil }
        let providerBundleID = String(line[providerStart..<providerEnd])
        guard !providerBundleID.isEmpty else { return nil }

        let nameSearchStart = line.index(after: providerEnd)
        guard let nameStartQuote = line[nameSearchStart...].firstIndex(of: "\"") else { return nil }
        let nameStart = line.index(after: nameStartQuote)
        let nameRemainder = line[nameStart...]
        let nameEnd = nameRemainder.firstIndex(of: "\"")
            ?? nameRemainder.range(of: " [VPN:")?.lowerBound
            ?? line.endIndex
        let name = line[nameStart..<nameEnd].trimmingCharacters(in: .whitespaces)

        let statusValue = line[line.index(after: statusStart)..<statusEnd].lowercased()
        let status = VPNServiceStatus(rawValue: statusValue) ?? .invalid
        return VPNService(
            id: id,
            name: name,
            providerBundleID: providerBundleID,
            status: status,
            interfaceName: nil
        )
    }
}
