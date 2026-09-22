import Foundation
import YamlKit

public enum PageSpecLoader {
    /// Load PageSpec from YAML string
    public static func load(yamlString: String) throws -> PageSpec {
        guard let obj = try YamlKit.load(yaml: yamlString) else {
            throw PageSpecError.invalidYaml("Empty YAML document")
        }

        guard let dict = obj as? [String: Any] else {
            throw PageSpecError.invalidYaml("Root of YAML must be a mapping")
        }

        return try decodePageSpec(dict: dict)
    }

    /// Load PageSpec from file URL
    public static func load(fileURL: URL) throws -> PageSpec {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return try load(yamlString: content)
    }

    private static func decodePageSpec(dict: [String: Any]) throws -> PageSpec {
        guard let uuid = dict["uuid"] as? String else {
            throw PageSpecError.missingField("uuid")
        }
        guard let tenantUuid = dict["tenant_uuid"] as? String else {
            throw PageSpecError.missingField("tenant_uuid")
        }
        guard let shellUuid = dict["shell_uuid"] as? String else {
            throw PageSpecError.missingField("shell_uuid")
        }
        guard let slugAlias = dict["slug_alias"] as? String else {
            throw PageSpecError.missingField("slug_alias")
        }
        guard let title = dict["title"] as? String else {
            throw PageSpecError.missingField("title")
        }
        let targetEnvironment = dict["target_environment"] as? String ?? "PC-Desktop-1440"
        let purpose = dict["purpose"] as? String ?? ""
        let archetype = dict["archetype"] as? String ?? "catalog"

        // Parse blocks
        var blocks: [BlockSpec] = []
        if let rawBlocks = dict["blocks"] as? [[String: Any]] {
            for b in rawBlocks {
                let bId = b["id"] as? String ?? UUID().uuidString
                let bPrimitive = b["primitive"] as? String ?? "HeroBlock"
                let bTitle = b["title"] as? String
                let bDesc = b["description"] as? String
                blocks.append(BlockSpec(
                    id: bId,
                    primitive: bPrimitive,
                    title: bTitle,
                    description: bDesc
                ))
            }
        }

        // Parse states
        var states: [String: StateSpec] = [:]
        if let rawStates = dict["states"] as? [String: Any] {
            for (stateName, rawVal) in rawStates {
                if let stateDict = rawVal as? [String: Any] {
                    let badge = stateDict["badge"] as? String
                    let notice = stateDict["notice"] as? String
                    var acts: [String: String]? = nil
                    if let rawActs = stateDict["actions"] as? [String: Any] {
                        acts = rawActs.mapValues { "\($0)" }
                    }

                    var rec: RecoverySpec? = nil
                    if let rawRec = stateDict["recovery"] as? [String: Any] {
                        rec = RecoverySpec(
                            label: rawRec["label"] as? String,
                            target: rawRec["target"] as? String,
                            action: rawRec["action"] as? String
                        )
                    }

                    states[stateName] = StateSpec(badge: badge, notice: notice, actions: acts, recovery: rec)
                }
            }
        }

        // Parse route contract
        var routeContract: RouteContractSpec? = nil
        if let rawRoute = dict["route_contract"] as? [String: Any] {
            var inbound: InboundRouteSpec? = nil
            if let rawIn = rawRoute["inbound"] as? [String: Any] {
                let p = rawIn["path"] as? String
                var c: [String: String]? = nil
                if let rawC = rawIn["carry"] as? [String: Any] {
                    c = rawC.mapValues { "\($0)" }
                }
                inbound = InboundRouteSpec(path: p, carry: c)
            }
            routeContract = RouteContractSpec(inbound: inbound)
        }

        return PageSpec(
            uuid: uuid,
            tenantUuid: tenantUuid,
            shellUuid: shellUuid,
            slugAlias: slugAlias,
            title: title,
            targetEnvironment: targetEnvironment,
            purpose: purpose,
            archetype: archetype,
            blocks: blocks,
            states: states,
            routeContract: routeContract,
            truthAssertions: nil
        )
    }
}

public enum PageSpecError: Error, CustomStringConvertible {
    case invalidYaml(String)
    case missingField(String)

    public var description: String {
        switch self {
        case .invalidYaml(let msg): return "Invalid YAML: \(msg)"
        case .missingField(let f): return "Missing required field: \(f)"
        }
    }
}
