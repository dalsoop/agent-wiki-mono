import Foundation
import InteropKit
import StateRootKit

/// 함대 CLI가 capabilities에 주장한 키를 실측과 대조한다 (거짓말 탐지).
public struct DalCapProbe: Sendable, Equatable, Codable {
    public var cli: String
    public var ok: Bool
    public var tenantScoped: Bool?
    public var viewpoint: String?
    public var concurrentTenants: Bool?
    public var purpose: String?
    public var lies: [String]
    public var error: String?

    public init(
        cli: String, ok: Bool, tenantScoped: Bool?, viewpoint: String?,
        concurrentTenants: Bool?, purpose: String?, lies: [String], error: String?
    ) {
        self.cli = cli
        self.ok = ok
        self.tenantScoped = tenantScoped
        self.viewpoint = viewpoint
        self.concurrentTenants = concurrentTenants
        self.purpose = purpose
        self.lies = lies
        self.error = error
    }
}

public struct DalFleetDoctorReport: Sendable, Equatable, Codable {
    public var probes: [DalCapProbe]
    public var passed: Bool
    public var lieCount: Int
}

public enum DalFleetDoctor: Sendable {
    public static let fleetCLIs = [
        "dal-chem-ledger",
        "dal-energy-organ",
        "dal-hippocampus-recall",
        "dal-ganglia-select",
        "dal-asof-derive",
        "dal-dream-consolidate",
        "dal-space-coords",
    ]

    public static func probe(
        cliName: String,
        homeDirectory: String? = nil
    ) -> DalCapProbe {
        guard let path = locate(cliName, home: homeDirectory) else {
            return DalCapProbe(
                cli: cliName, ok: false, tenantScoped: nil, viewpoint: nil,
                concurrentTenants: nil, purpose: nil,
                lies: ["CLI missing"], error: "not on PATH"
            )
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["capabilities", "--json"]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return DalCapProbe(
                cli: cliName, ok: false, tenantScoped: nil, viewpoint: nil,
                concurrentTenants: nil, purpose: nil,
                lies: ["spawn failed"], error: error.localizedDescription
            )
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let obj = DalJSON.object(from: data) else {
            return DalCapProbe(
                cli: cliName, ok: false, tenantScoped: nil, viewpoint: nil,
                concurrentTenants: nil, purpose: nil,
                lies: ["capabilities not JSON"], error: "parse"
            )
        }
        let result = (obj["result"] as? [String: Any]) ?? obj
        let tenantScoped = result["tenantScoped"] as? Bool
        let viewpoint = result["viewpoint"] as? String
        let concurrent = result["concurrentTenants"] as? Bool
        let purpose = result["purpose"] as? String
        var lies: [String] = []
        if tenantScoped != true { lies.append("tenantScoped!=true") }
        if viewpoint != "first" { lies.append("viewpoint!=first") }
        if concurrent != true { lies.append("concurrentTenants!=true") }
        if (purpose ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lies.append("purpose empty")
        }
        return DalCapProbe(
            cli: cliName,
            ok: lies.isEmpty && proc.terminationStatus == 0,
            tenantScoped: tenantScoped,
            viewpoint: viewpoint,
            concurrentTenants: concurrent,
            purpose: purpose,
            lies: lies,
            error: proc.terminationStatus == 0 ? nil : "exit \(proc.terminationStatus)"
        )
    }

    public static func runAll(homeDirectory: String? = nil) -> DalFleetDoctorReport {
        let probes = fleetCLIs.map { probe(cliName: $0, homeDirectory: homeDirectory) }
        let lieCount = probes.reduce(0) { $0 + $1.lies.count }
        return DalFleetDoctorReport(
            probes: probes,
            passed: probes.allSatisfy(\.ok),
            lieCount: lieCount
        )
    }

    private static func locate(_ name: String, home: String?) -> String? {
        let homePath = home ?? StateRootKit.resolveHost()
        let candidates = [
            HostPlatform.cliBinPath(name),
            "/usr/local/bin/\(name)",
            (homePath as NSString).appendingPathComponent(".local/bin/\(name)"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
