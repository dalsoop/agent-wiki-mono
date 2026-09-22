import AgentSurfaceKit
import Foundation

/// Agent Wiki coding-agent surface — skills attached on install / skill-install.
public enum AgentSurface {
    public static let profile = AgentSurfaceProfile(
        ownerCLI: DualEntry.cliProductName,
        skills: ["agent-wiki"],
        agents: [],
        preferCatalogSymlink: true
    )

    public static func attach(seedBundle: Bundle = .main) throws -> AgentSurfaceRules.AttachResult {
        try AgentSurfaceGate.attach(profile: profile, seeds: .init(), seedBundle: seedBundle)
    }

    public static func detach() throws -> AgentSurfaceRules.AttachResult {
        try AgentSurfaceRules.detach(profile: profile)
    }

    public static func status() -> AgentSurfaceRules.Status {
        AgentSurfaceRules.status(profile: profile)
    }
}
