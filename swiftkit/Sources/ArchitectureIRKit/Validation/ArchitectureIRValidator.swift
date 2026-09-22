import Foundation

public struct ValidationError: Sendable, Equatable, CustomStringConvertible {
    public enum Severity: String, Sendable {
        case error
        case warning
    }

    public var severity: Severity
    public var rule: String
    public var targetId: String?
    public var message: String

    public var description: String {
        "[\(severity.rawValue.uppercased())] [\(rule)] \(targetId.map { "(\($0)) " } ?? "")\(message)"
    }
}

public struct ValidationReport: Sendable, Equatable {
    public var isValid: Bool { errors.isEmpty }
    public var issues: [ValidationError]

    public var errors: [ValidationError] {
        issues.filter { $0.severity == .error }
    }

    public var warnings: [ValidationError] {
        issues.filter { $0.severity == .warning }
    }
}

public enum ArchitectureIRValidator {
    public static func validate(_ document: ArchitectureIRDocument) -> ValidationReport {
        var issues: [ValidationError] = []
        let nodeIds = Set(document.nodes.map(\.id))
        
        validateNodeDuplicates(document.nodes, nodeIds: nodeIds, issues: &issues)
        validateNodes(document.nodes, issues: &issues)
        validateEdges(document.edges, nodeIds: nodeIds, issues: &issues)

        return ValidationReport(issues: issues)
    }

    private static func validateNodeDuplicates(_ nodes: [ArchitectureNode], nodeIds: Set<String>, issues: inout [ValidationError]) {
        guard nodeIds.count != nodes.count else { return }
        var seen: Set<String> = []
        for node in nodes {
            if seen.contains(node.id) {
                issues.append(ValidationError(
                    severity: .error,
                    rule: "DuplicateNodeId",
                    targetId: node.id,
                    message: "노드 ID가 중복되었습니다: \(node.id)"
                ))
            }
            seen.insert(node.id)
        }
    }

    private static let wikiIdRegex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(pattern: "^[0-9a-f]{8}$")
        } catch {
            return nil
        }
    }()

    private static func validateNodes(_ nodes: [ArchitectureNode], issues: inout [ValidationError]) {
        for node in nodes {
            validateNodePrefix(node, issues: &issues)
            validateNodeWikiId(node, regex: wikiIdRegex, issues: &issues)
            validateNodeTetrahedron(node, issues: &issues)
        }
    }

    private static func validateNodePrefix(_ node: ArchitectureNode, issues: inout [ValidationError]) {
        let prefix = "\(node.type.rawValue):"
        guard !node.id.hasPrefix(prefix) else { return }
        issues.append(ValidationError(
            severity: .error,
            rule: "NodeIdFormatMismatch",
            targetId: node.id,
            message: "노드 ID는 '\(prefix)' 접두어로 시작해야 합니다."
        ))
    }

    private static func validateNodeWikiId(_ node: ArchitectureNode, regex: NSRegularExpression?, issues: inout [ValidationError]) {
        guard let wikiId = node.wikiId else { return }
        let range = NSRange(location: 0, length: wikiId.utf16.count)
        guard regex?.firstMatch(in: wikiId, range: range) == nil else { return }
        issues.append(ValidationError(
            severity: .error,
            rule: "InvalidWikiIdFormat",
            targetId: node.id,
            message: "gujo-wiki ID는 8자리 16진수여야 합니다: \(wikiId)"
        ))
    }

    private static func validateNodeTetrahedron(_ node: ArchitectureNode, issues: inout [ValidationError]) {
        guard node.type == .app && node.tetrahedron.grade == "unreached" else { return }
        issues.append(ValidationError(
            severity: .warning,
            rule: "TetrahedronUnreached",
            targetId: node.id,
            message: "앱의 4면체 완성도가 'unreached'(0.0) 상태입니다. 표면 보완이 필요합니다."
        ))
    }

    private static func validateEdges(_ edges: [ArchitectureEdge], nodeIds: Set<String>, issues: inout [ValidationError]) {
        for edge in edges {
            validateEdgeEndpoints(edge, nodeIds: nodeIds, issues: &issues)
            validateEdgeContract(edge, issues: &issues)
        }
    }

    private static func validateEdgeEndpoints(_ edge: ArchitectureEdge, nodeIds: Set<String>, issues: inout [ValidationError]) {
        if !nodeIds.contains(edge.source) {
            issues.append(ValidationError(
                severity: .error,
                rule: "OrphanEdgeSource",
                targetId: edge.id,
                message: "엣지의 source 노드가 존재하지 않습니다: \(edge.source)"
            ))
        }
        if !nodeIds.contains(edge.target) {
            issues.append(ValidationError(
                severity: .error,
                rule: "OrphanEdgeTarget",
                targetId: edge.id,
                message: "엣지의 target 노드가 존재하지 않습니다: \(edge.target)"
            ))
        }
    }

    private static func validateEdgeContract(_ edge: ArchitectureEdge, issues: inout [ValidationError]) {
        if edge.type == .dependsOn && edge.contract.kind != .directImport {
            issues.append(ValidationError(
                severity: .warning,
                rule: "ContractMismatchDependsOn",
                targetId: edge.id,
                message: "dependsOn 관계는 directImport 계약이어야 합니다."
            ))
        }

        if edge.contract.riskLevel == .criticalViolation {
            issues.append(ValidationError(
                severity: .error,
                rule: "ProcessConstitutionViolation",
                targetId: edge.id,
                message: "날것의 Process() 또는 비표준 프로세스 실행이 감지되었습니다. CommandKit으로 전환해야 합니다."
            ))
        }
    }
}
