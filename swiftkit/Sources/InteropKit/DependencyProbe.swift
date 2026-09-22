import Foundation

/// capabilities.depends 항목 존재 검사. 설치·doctor·스윕이 공유.
public struct DependencyProbe: Sendable {
    public struct Finding: Equatable, Sendable {
        public let id: String
        public let kind: String
        public let ref: String
        public let required: Bool
        public let ok: Bool
        public let status: String
        public let detail: String
        public init(id: String, kind: String, ref: String, required: Bool, ok: Bool, status: String, detail: String) {
            self.id = id; self.kind = kind; self.ref = ref; self.required = required
            self.ok = ok; self.status = status; self.detail = detail
        }
    }
    public struct Report: Equatable, Sendable {
        public let findings: [Finding]
        public var ok: Bool { findings.allSatisfy { !$0.required || $0.ok } }
        public init(findings: [Finding]) { self.findings = findings }
    }
    // FileManager is not Sendable; keep only value types. Tests inject via pathEnv.
    private let pathEnv: String
    private let homebrewPrefix: String
    public init(fileManager: FileManager = .default, pathEnv: String? = nil, homebrewPrefix: String = HostPlatform.homebrewPrefix) {
        _ = fileManager // API 호환: 주입 시그니처 유지, 호출마다 .default 사용
        self.pathEnv = pathEnv ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        self.homebrewPrefix = homebrewPrefix
    }
    private var fileManager: FileManager { .default }
    public func probe(_ dependencies: [Capabilities.Dependency]) -> Report {
        Report(findings: dependencies.map(probeOne))
    }
    private func probeOne(_ dep: Capabilities.Dependency) -> Finding {
        switch dep.kind {
        case Capabilities.DependencyKind.command, Capabilities.DependencyKind.brewFormula, Capabilities.DependencyKind.brewCask:
            return probeCommand(dep)
        case Capabilities.DependencyKind.cli:
            return probeCLI(dep)
        case Capabilities.DependencyKind.path:
            let path = Capabilities.expandingTilde(dep.ref)
            let exists = fileManager.fileExists(atPath: path)
            return Finding(id: dep.id, kind: dep.kind, ref: dep.ref, required: dep.required, ok: exists, status: exists ? "present" : "missing", detail: exists ? path : "path not found: \(path)")
        case Capabilities.DependencyKind.permission, Capabilities.DependencyKind.credential:
            return Finding(id: dep.id, kind: dep.kind, ref: dep.ref, required: dep.required, ok: true, status: "unchecked", detail: "declaration-only in probe v1")
        default:
            return Finding(id: dep.id, kind: dep.kind, ref: dep.ref, required: dep.required, ok: true, status: "unknown-kind", detail: "not probed")
        }
    }
    private func probeCommand(_ dep: Capabilities.Dependency) -> Finding {
        if let path = resolveExecutable(dep.ref) {
            return Finding(id: dep.id, kind: dep.kind, ref: dep.ref, required: dep.required, ok: true, status: "present", detail: path)
        }
        return Finding(id: dep.id, kind: dep.kind, ref: dep.ref, required: dep.required, ok: false, status: "missing", detail: "not found on PATH")
    }
    private func probeCLI(_ dep: Capabilities.Dependency) -> Finding {
        for path in ["\(homebrewPrefix)/bin/\(dep.ref)", "\(NSHomeDirectory())/.local/bin/\(dep.ref)"] where fileManager.isExecutableFile(atPath: path) {
            return Finding(id: dep.id, kind: dep.kind, ref: dep.ref, required: dep.required, ok: true, status: "present", detail: path)
        }
        if let path = resolveExecutable(dep.ref) {
            return Finding(id: dep.id, kind: dep.kind, ref: dep.ref, required: dep.required, ok: true, status: "present", detail: path)
        }
        return Finding(id: dep.id, kind: dep.kind, ref: dep.ref, required: dep.required, ok: false, status: "missing", detail: "CLI not found")
    }
    private func resolveExecutable(_ name: String) -> String? {
        if name.hasPrefix("/") { return fileManager.isExecutableFile(atPath: name) ? name : nil }
        for dir in pathEnv.split(separator: ":") {
            let path = "\(dir)/\(name)"
            if fileManager.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
